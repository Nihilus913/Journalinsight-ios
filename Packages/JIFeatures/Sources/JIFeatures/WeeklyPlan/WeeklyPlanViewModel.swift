import Foundation
import Observation
import JICore
import JIDesign

// W5b-L5 (P-weekly-plan). Port of `mobile/app/weekly-plan.tsx`'s state. Seeding priority is the
// oracle's, verbatim: 1) a persisted prefs row from a prior save, 2) the goals document
// (`EnergyProviding.goals()` — consumed, never redefined), 3) the hardcoded fallback.
// B-57 W1 r4 (board `3 Plan & train/04 WeeklyPlan.png`): edits are staged and "Save plan"
// persists them (it replaced RN's write-through-on-every-tap).

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
    /// The user's calorie goal from the goals document — what "Matches your goal" is checked
    /// against. `nil` when there is no goals provider, it failed, or no goal is set.
    public private(set) var goalKcal: Double?
    /// What the store holds (nil = never saved) — "Save plan" is live only when the screen differs.
    private var savedPrefs: WeeklyPlanPrefs?

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

    /// Board status line under the hero: the plan's weekly average against the user's goal.
    public var goalStatus: WeeklyPlanGoalStatus { weeklyPlanGoalStatus(avgKcal: plan.avgKcal, goalKcal: goalKcal) }

    private var currentPrefs: WeeklyPlanPrefs {
        WeeklyPlanPrefs(weeklyAvgKcal: weeklyAvgKcal, trainKcal: trainKcal, proteinG: proteinG, fatG: fatG)
    }

    /// "Save plan" is enabled while the plan on screen is not what the store holds.
    public var canSave: Bool { currentPrefs != savedPrefs }

    /// "Save plan": the one write path (`WeeklyPlanStore.save`).
    public func save() {
        let prefs = currentPrefs
        store.save(prefs)
        savedPrefs = prefs
        hasSaved = true
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
            savedPrefs = prefs
            goalsSeeded = true
        }
        guard let goalsProvider else { return }
        // A hub failure here is not an error state: the screen is fully usable on the fallback
        // numbers (rule 5 — never a zero, never a blank screen); the status line says "No goal set".
        guard let goals = try? await goalsProvider.goals() else { return }
        goalKcal = goals.nutrition.kcalGoal
        guard !goalsSeeded else { return }
        goalsSeeded = true
        let avg = goals.nutrition.kcalGoal ?? 1800
        weeklyAvgKcal = avg
        trainKcal = avg + Self.defaultTrainBoost
        if let protein = goals.nutrition.proteinG { proteinG = protein }
        if let fat = goals.nutrition.fatG { fatG = fat }
    }

    // MARK: edits (RN `onWeeklyAvg`/`onTrainKcal`/`onProtein`/`onFat`)

    public func setWeeklyAvgKcal(_ value: Double) { weeklyAvgKcal = value; edited() }
    public func setTrainKcal(_ value: Double) { trainKcal = value; edited() }
    public func setProteinG(_ value: Double) { proteinG = value; edited() }
    public func setFatG(_ value: Double) { fatG = value; edited() }

    /// RN's `Stepper` handlers: `Math.max(min, value - step)` / `value + step`.
    public func step(_ knob: Knob, by delta: Double) {
        switch knob {
        case .weeklyAvg: setWeeklyAvgKcal(max(1200, weeklyAvgKcal + delta))
        case .trainKcal:
            // B-57 W1 fixer: step from the target the screen shows (a held target, when capped),
            // and never past what the rest days can fund — a "+" that changes nothing on screen
            // while the stored number climbs would be a lie.
            let ceiling = weeklyPlanMaxTrainKcal(weeklyAvgKcal: weeklyAvgKcal, proteinG: proteinG, fatG: fatG) ?? .infinity
            setTrainKcal(min(ceiling, max(weeklyAvgKcal, value(of: .trainKcal) + delta)))
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
            case .protein: "Protein, every day"
            case .fat: "Fat, every day"
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
        case .trainKcal: plan.trainCapped ? Double(plan.trainKcal) : trainKcal
        case .protein: proteinG
        case .fat: fatG
        }
    }

    /// A user edit always wins over a lagging goals seed; the "Saved." line goes until the next save.
    private func edited() {
        goalsSeeded = true
        hasSaved = false
    }
}

/// Renders a knob the way RN's `{value}` does: a whole number carries no decimal point, a goals-
/// seeded value like `184.9 g` keeps its fraction rather than being silently rounded away.
public nonisolated func weeklyPlanNumberText(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
}

/// The board's status line under the weekly-average hero.
public nonisolated struct WeeklyPlanGoalStatus: Equatable, Sendable {
    public let word: String
    public let role: JIColorRole
    public let symbolName: String
    public init(word: String, role: JIColorRole, symbolName: String) {
        self.word = word; self.role = role; self.symbolName = symbolName
    }
}

/// The plan's weekly average against the user's calorie goal, to the whole kcal the screen shows.
public nonisolated func weeklyPlanGoalStatus(avgKcal: Int, goalKcal: Double?) -> WeeklyPlanGoalStatus {
    guard let goalKcal, goalKcal.isFinite else {
        return WeeklyPlanGoalStatus(word: "No goal set", role: .muted, symbolName: "minus")
    }
    let goal = Int(jsRound(goalKcal))
    let diff = avgKcal - goal
    if diff == 0 { return WeeklyPlanGoalStatus(word: "Matches your goal", role: .go, symbolName: "checkmark") }
    return WeeklyPlanGoalStatus(word: "\(abs(diff)) kcal \(diff > 0 ? "above" : "below") your goal of \(goal)",
                                role: .reduced, symbolName: diff > 0 ? "arrow.up" : "arrow.down")
}
