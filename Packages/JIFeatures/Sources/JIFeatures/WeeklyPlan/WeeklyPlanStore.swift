import Foundation
import JIPersistence

// W5b-L5 (P-weekly-plan). Port of `mobile/src/lib/weeklyPlanStore.ts`: the persisted knobs for the
// periodized editor (E12-8). RN keeps them in the shared `local_prefs` sqlite file via
// `getLocalPref`/`setLocalPref`; the Swift counterpart of that seam is `JIPersistence.PrefStore`
// (the same store `EditToday`/`KpiSelection` persist through), keyed identically.
//
// Every edit on the screen writes through immediately (no Save button — see the screen's own
// comment), so this is the single source of truth for "what did the user last set", read once at
// mount and otherwise left alone until the next edit.

public nonisolated struct WeeklyPlanPrefs: Codable, Sendable, Equatable {
    public var weeklyAvgKcal: Double
    public var trainKcal: Double
    public var proteinG: Double
    public var fatG: Double

    public init(weeklyAvgKcal: Double, trainKcal: Double, proteinG: Double, fatG: Double) {
        self.weeklyAvgKcal = weeklyAvgKcal; self.trainKcal = trainKcal
        self.proteinG = proteinG; self.fatG = fatG
    }
}

/// Thin wrapper over `PrefStore` under the oracle's key. A `nil` store (no database yet) is a
/// no-op on both sides rather than a crash — same discipline as `loadTodayTilePrefs(prefs:)`.
public nonisolated struct WeeklyPlanStore: Sendable {
    /// Verbatim `WEEKLY_PLAN_PREFS_KEY` from the oracle.
    public static let prefKey = "weekly_plan.periodized"

    private let prefs: PrefStore?

    public init(prefs: PrefStore?) { self.prefs = prefs }

    /// The on-disk store the Nutrition-tab entry uses: `RootTabView` never threads `env.prefs`
    /// into `NutritionView` (that file is another lane's, and the card allows this lane exactly
    /// ONE navigation line there), so the screen resolves the same backed-up
    /// `journalinsight.sqlite` file itself — the idiom `RootTabView.swift` L34-38 already
    /// documents for the Journal tab (GRDB supports several pools against one file). Lazily
    /// initialised by Swift's `static let` semantics, so nothing opens a database until the
    /// weekly-plan screen is first reached, and a failure degrades to "not persisted", never a
    /// crash (rule 5: the screen still renders, it just can't remember).
    public static let onDisk = WeeklyPlanStore(prefs: (try? AppDatabase.onDisk()).map { PrefStore(db: $0) })

    public func load() -> WeeklyPlanPrefs? {
        (try? prefs?.get(Self.prefKey, as: WeeklyPlanPrefs.self)) ?? nil
    }

    public func save(_ value: WeeklyPlanPrefs) {
        try? prefs?.set(Self.prefKey, value)
    }
}
