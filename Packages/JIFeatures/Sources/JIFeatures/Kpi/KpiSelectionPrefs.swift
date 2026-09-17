import Foundation

/// W3b-L2 — "My KPIs" selection: which of the 12 `KpiMetricId`s show on the list's preview /
/// widget, and in what order. Ported from the oracle's `src/kpi/kpiSelectionPrefs.ts`, but
/// persisted through `PrefStore` (JIPersistence, GRDB `pref` table) rather than the RN app's
/// `local_prefs.db` — this app has no equivalent generic local-prefs store yet, and `PrefStore`
/// is the one already frozen/consumable this wave (card: "PrefStore (JIPersistence) for
/// selection").
public nonisolated struct KpiSelectionPrefs: Codable, Sendable, Equatable {
    /// ALL 12 `KpiMetricId`s, ranked — "how much I care", most first.
    public var order: [KpiMetricId]
    /// Subset of `order` NOT in "My KPIs".
    public var hidden: [KpiMetricId]
    public init(order: [KpiMetricId], hidden: [KpiMetricId]) { self.order = order; self.hidden = hidden }
}

/// Picker floor/ceiling + defaults + the pure edit operations. `PrefStore` read/write is the
/// view model's job (`KpiListViewModel`); everything here is a pure function of a
/// `KpiSelectionPrefs` value, same shape as the oracle module.
public nonisolated enum KpiSelection {
    public static let prefKey = "kpi_selection.prefs.v1"
    public static let minSelected = 3
    public static let maxSelected = 8

    // Union of Today's pre-existing 4 chips (hrv, rhr, sleep, steps) and Recovery's 6 rows —
    // mirrors the oracle's DEFAULT_KPI_ORDER/DEFAULT_KPI_HIDDEN exactly.
    public static let defaultOrder: [KpiMetricId] = [.hrv, .rhr, .sleep, .steps, .bodyBattery, .readiness, .acwr, .weight, .kcal, .protein, .carbs, .fat]
    public static let defaultHidden: [KpiMetricId] = [.weight, .kcal, .protein, .carbs, .fat]

    public static func defaultPrefs() -> KpiSelectionPrefs { KpiSelectionPrefs(order: defaultOrder, hidden: defaultHidden) }

    /// Drops any id no longer registered and appends, in registry order, any id the current
    /// `KpiMetricId.allCases` declares that a persisted (possibly stale/legacy/nil) blob predates
    /// — a newly-registered id defaults to hidden. Never throws; falls back to the full default.
    public static func reconcile(_ raw: KpiSelectionPrefs?) -> KpiSelectionPrefs {
        guard let raw, !raw.order.isEmpty else { return defaultPrefs() }
        let known = Set(KpiMetricId.allCases)
        let savedOrder = raw.order.filter { known.contains($0) }
        let seen = Set(savedOrder)
        let missing = KpiMetricId.allCases.filter { !seen.contains($0) }
        let order = savedOrder + missing
        let orderSet = Set(order)
        var hidden = raw.hidden.filter { orderSet.contains($0) && known.contains($0) }
        var hiddenSet = Set(hidden)
        for id in missing where !hiddenSet.contains(id) { hidden.append(id); hiddenSet.insert(id) }
        return KpiSelectionPrefs(order: order, hidden: hidden)
    }

    /// `prefs.order` filtered to the selected subset, in rank order.
    public static func visibleOrder(_ prefs: KpiSelectionPrefs) -> [KpiMetricId] {
        let hiddenSet = Set(prefs.hidden)
        return prefs.order.filter { !hiddenSet.contains($0) }
    }

    /// Returns the SAME `prefs` value (detectable by `==`) when the change would push the
    /// selected count below `minSelected` or above `maxSelected` — never clamps silently.
    public static func setSelected(_ prefs: KpiSelectionPrefs, id: KpiMetricId, selected: Bool) -> KpiSelectionPrefs {
        var hiddenSet = Set(prefs.hidden)
        let isHidden = hiddenSet.contains(id)
        if selected == !isHidden { return prefs }
        let selectedCount = prefs.order.count - prefs.hidden.count
        if selected && selectedCount >= maxSelected { return prefs }
        if !selected && selectedCount <= minSelected { return prefs }
        if selected { hiddenSet.remove(id) } else { hiddenSet.insert(id) }
        return KpiSelectionPrefs(order: prefs.order, hidden: prefs.order.filter { hiddenSet.contains($0) })
    }

    /// Moves `id` one slot earlier (-1) or later (+1) among the currently SELECTED ids only —
    /// a no-op (same value) at either end of the visible list, or when `id` is itself hidden.
    public static func move(_ prefs: KpiSelectionPrefs, id: KpiMetricId, direction: Int) -> KpiSelectionPrefs {
        var visible = visibleOrder(prefs)
        guard let idx = visible.firstIndex(of: id) else { return prefs }
        let swapIdx = idx + direction
        guard visible.indices.contains(swapIdx) else { return prefs }
        visible.swapAt(idx, swapIdx)
        let hiddenSet = Set(prefs.hidden)
        var visIdx = 0
        let newOrder = prefs.order.map { entry -> KpiMetricId in
            if hiddenSet.contains(entry) { return entry }
            defer { visIdx += 1 }
            return visible[visIdx]
        }
        return KpiSelectionPrefs(order: newOrder, hidden: prefs.hidden)
    }
}
