import Foundation
import Observation
import JICore
import JICompute
import JIPersistence

/// B-73: the one place the phone turns Health totals + the user's goals into the plan band.
/// Energy, the goal ticks and the macro widget all read this, never Health directly.
/// - band = the user's kcal target ± 100 (exists whenever a kcal goal is set; no Health needed);
/// - burn, balance and the implied deficit need ≥ 3 complete Health days ("Calibrating" below).
/// `refresh()` runs on each foreground (App wiring, Task C5). It keeps the last good totals in
/// `OfflineCache`, so a failed read still shows yesterday's numbers. It never talks to the hub:
/// the only hub push is a user save in GoalsSetup (`GoalsMirror`, TEMP until B-50).
@Observable @MainActor
public final class EnergyBandService {
    public static let cacheKey = "energy.healthTotals"
    public private(set) var totals: [HealthDailyTotals] = []
    public private(set) var burnWindow: EnergyBurnWindow?
    public private(set) var result: EnergyBandResult?
    /// The Health side only: "Not in Health yet", "Calibrating", or nil when the burn is known.
    public private(set) var reasonWord: String?
    public private(set) var fetchedAt: Date?
    public private(set) var goals: MacroGoals?

    private let reader: (any HealthDailyTotalsProviding)?
    private let store: MacroGoalsStore
    private let cache: OfflineCache
    private let now: () -> Date
    private let dayKey: (Date) -> String

    public nonisolated static func localDayKey(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    public init(reader: (any HealthDailyTotalsProviding)?, store: MacroGoalsStore, cache: OfflineCache,
                now: @escaping () -> Date = Date.init, dayKey: @escaping (Date) -> String = EnergyBandService.localDayKey) {
        self.reader = reader; self.store = store; self.cache = cache; self.now = now; self.dayKey = dayKey
    }

    /// One window + today: 7 complete-day candidates for the burn, plus today for "left today".
    private static let readDays = EnergyBand.windowDays + 1

    public func refresh() async {
        if totals.isEmpty, let hit = try? cache.get(Self.cacheKey, as: [HealthDailyTotals].self) {
            totals = hit.value; fetchedAt = hit.fetchedAt
        }
        if let reader, let fresh = try? await reader.dailyTotals(days: Self.readDays) {
            totals = fresh
            fetchedAt = now()
            try? cache.put(Self.cacheKey, fresh)
        }
        recompute()
    }

    /// Recomputes from `totals` + the stored goals (GoalsSetup calls it after a save).
    public func recompute() {
        goals = try? store.load()
        let key = dayKey(now())
        let days = totals.map { EnergyBandDay(date: $0.date, basalKcal: $0.basalKcal, activeKcal: $0.activeKcal, intakeKcal: $0.dietaryKcal) }
        let hasHealth = totals.contains(where: \.hasAnyValue)
        burnWindow = hasHealth ? EnergyBand.burnWindow(days: days, today: key) : nil
        result = goals?.targetKcal.map { EnergyBand.compute(targetKcal: $0, days: days, today: key) }
        if !hasHealth { reasonWord = "Not in Health yet" }
        else if burnWindow?.calibrating ?? true { reasonWord = "Calibrating" }
        else { reasonWord = nil }
    }

    public var today: HealthDailyTotals? { totals.first { $0.date == dayKey(now()) } }
    /// The user's kcal target (nil = "Set your goal").
    public var kcalTarget: Double? { goals?.targetKcal }
    public var needsGoal: Bool { goals?.kcal == nil }

    public var snapshot: NutritionGoalsSnapshot { NutritionGoalsSnapshot(macros: goals) }
}
