import Foundation
import Observation
import JICore

// W5b-L5 (P-weekly-plan). Port of `mobile/app/weekly-plan.tsx`'s state. Seeding priority is the
// oracle's, verbatim: 1) a persisted prefs row from a prior edit, 2) the goals document
// (`EnergyProviding.goals()` — consumed, never redefined), 3) the hardcoded fallback. Every edit
// writes through immediately — no Save button.

@Observable @MainActor
public final class WeeklyPlanViewModel {
    /// RN `DEFAULT_TRAIN_BOOST` — the fallback boost when there is neither a persisted prefs row
    /// nor a goals document yet (first-ever launch, provider still loading).
    public static let defaultTrainBoost: Double = 400

    public private(set) var weeklyAvgKcal: Double = 1800
    public private(set) var trainKcal: Double = 1800 + WeeklyPlanViewModel.defaultTrainBoost
    public private(set) var proteinG: Double = 165
    public private(set) var fatG: Double = 55
    /// RN `savedAt != null` → the "Saved." line.
    public private(set) var hasSaved = false

    private let store: WeeklyPlanStore
    private let goalsProvider: (any EnergyProviding)?
    /// RN `goalsSeeded` ref. Set by the seed itself AND by the first user edit: `goals()` can
    /// still be in flight when the user makes that edit (slow network, cold cache), and without
    /// this the response landing a moment later would silently clobber it. A user edit always
    /// wins over a lagging seed, unconditionally.
    private var goalsSeeded = false

    public init(store: WeeklyPlanStore, goalsProvider: (any EnergyProviding)? = nil) {
        self.store = store
        self.goalsProvider = goalsProvider
    }

    public var plan: PeriodizedPlan {
        computePeriodizedPlan(
            PeriodizedPlanInput(weeklyAvgKcal: weeklyAvgKcal, trainKcal: trainKcal, proteinG: proteinG, fatG: fatG)
        )
    }

    /// RN's two sequenced effects: read the persisted prefs first, and only seed from goals when
    /// that read resolved AND found nothing.
    public func load() async {
        if let prefs = store.load() {
            weeklyAvgKcal = prefs.weeklyAvgKcal
            trainKcal = prefs.trainKcal
            proteinG = prefs.proteinG
            fatG = prefs.fatG
            goalsSeeded = true
            return
        }
        guard let goalsProvider, !goalsSeeded else { return }
        // A hub failure here is not an error state: the screen is fully usable on the fallback
        // numbers (rule 5 — never a zero, never a blank screen).
        guard let goals = try? await goalsProvider.goals(), !goalsSeeded else { return }
        goalsSeeded = true
        let avg = goals.nutrition.kcalGoal ?? 1800
        weeklyAvgKcal = avg
        trainKcal = avg + Self.defaultTrainBoost
        if let protein = goals.nutrition.proteinG { proteinG = protein }
        if let fat = goals.nutrition.fatG { fatG = fat }
    }

    // MARK: edits (RN `onWeeklyAvg`/`onTrainKcal`/`onProtein`/`onFat`)

    public func setWeeklyAvgKcal(_ value: Double) { weeklyAvgKcal = value; persist() }
    public func setTrainKcal(_ value: Double) { trainKcal = value; persist() }
    public func setProteinG(_ value: Double) { proteinG = value; persist() }
    public func setFatG(_ value: Double) { fatG = value; persist() }

    /// RN's `Stepper` handlers: `Math.max(min, value - step)` / `value + step`.
    public func step(_ knob: Knob, by delta: Double) {
        switch knob {
        case .weeklyAvg: setWeeklyAvgKcal(max(1200, weeklyAvgKcal + delta))
        case .trainKcal: setTrainKcal(max(weeklyAvgKcal, trainKcal + delta))
        case .protein: setProteinG(max(80, proteinG + delta))
        case .fat: setFatG(max(30, fatG + delta))
        }
    }

    public enum Knob: String, Sendable, CaseIterable {
        case weeklyAvg, trainKcal, protein, fat

        public var label: String {
            switch self {
            case .weeklyAvg: "Weekly average"
            case .trainKcal: "Training-day target"
            case .protein: "Protein (every day)"
            case .fat: "Fat (every day)"
            }
        }

        public var unit: String {
            switch self {
            case .weeklyAvg, .trainKcal: "kcal"
            case .protein, .fat: "g"
            }
        }

        public var stepSize: Double {
            switch self {
            case .weeklyAvg, .trainKcal: 50
            case .protein, .fat: 5
            }
        }
    }

    public func value(of knob: Knob) -> Double {
        switch knob {
        case .weeklyAvg: weeklyAvgKcal
        case .trainKcal: trainKcal
        case .protein: proteinG
        case .fat: fatG
        }
    }

    private func persist() {
        goalsSeeded = true
        store.save(WeeklyPlanPrefs(weeklyAvgKcal: weeklyAvgKcal, trainKcal: trainKcal, proteinG: proteinG, fatG: fatG))
        hasSaved = true
    }
}

/// Renders a knob the way RN's `{value}` does: a whole number carries no decimal point, a goals-
/// seeded value like `184.9 g` keeps its fraction rather than being silently rounded away.
public nonisolated func weeklyPlanNumberText(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
}
