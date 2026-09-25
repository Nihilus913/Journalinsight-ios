import Foundation
import JICore
import JIDesign
import JIPersistence

// W5a-L3 (P-edit-today). Port of `mobile/src/components/TodayTileRegistry.tsx` (labels) +
// `mobile/src/data/todayTilePrefs.ts` (the pure prefs ops). RN's tile set (streak, mind, weight,
// kcal_ring, strength, week_strip) maps onto the Swift Today's customizable set: the four
// `TodayChip`s `TodayViewModel.chips` renders (hrv/rhr/sleep/steps, fixed ids) plus the B-57 board's
// Load/Protein/Calories/Weight (`TodayViewModel.squareChips`). The verdict hero,
// the EA gated tile and the Mind tile are NOT in this registry — RN forbids removing/reordering
// the verdict ("the screen's job") and the other two aren't in `TodayGrid`'s order array.
//
// Storage: `today.tileOrder` (`[String]`, FULL order incl. hidden — RN `prefs.order`) is the key
// `TodayGrid.swift` already reads/writes, so a Today drag and an Edit-Today arrow agree byte for
// byte. `today.tileHidden` (`[String]`, subset of order — RN `prefs.hidden`) is new here.
// `nonisolated`: pure values + functions, usable from nonisolated tests (JIFeatures' default is MainActor).

public nonisolated let todayTileHiddenKey = "today.tileHidden"

/// W-FIX3 C-a: set once EditToday's set has been folded into `KpiSelection.prefKey` — from then on
/// that ONE selection is what Today, EditToday and My KPIs ("On Today") all read and write.
public nonisolated let todayTilesUnifiedKey = "today.tiles.unified.v1"

/// W-FIX3 C-a: posted after every write of the Today squares, so a Today behind a closing sheet
/// (Settings → Edit Today, My KPIs) re-reads them at once instead of on its next appearance.
public nonisolated let todayTilePrefsDidChange = Notification.Name("ji.todayTilePrefsDidChange")

public nonisolated enum TodayTileRegistry {
    /// Every `TodayChip.id` in `TodayViewModel.squareChips` order: Today's four grid chips (= RN
    /// `DEFAULT_TODAY_TILE_ORDER`) then the B-57 board's Load, Protein, Calories, Weight (ids are
    /// `KpiMetricId` raw values, so a tap lands on the same KPI). Tests pin this against a live VM.
    /// W-FIX3 C-a: then every other KPI My KPIs can tick (`optInIds`, hidden until picked), so the
    /// two screens can never disagree — every `KpiMetricId` is a possible Today square.
    public static let ids: [String] = ["hrv", "rhr", "sleep", "steps", "acwr", "protein", "kcal", "weight"] + optInIds
    /// Squares added in W-FIX3; a stored set that predates them gets them hidden, never pushed on Today.
    public static let optInIds: [String] = ["body_battery", "readiness", "carbs", "fat"]

    /// RN `TODAY_TILE_LABELS` — `TodayChip.label` for each id.
    public static func label(for id: String) -> String {
        switch id {
        case "hrv": "HRV"
        case "rhr": "RHR"
        case "sleep": "Sleep"
        case "steps": "Steps"
        case "acwr": "Load"
        case "protein": "Protein"
        case "kcal": "Calories"
        case "weight": "Weight"
        case "body_battery": "Body Battery"
        case "readiness": "Readiness"
        case "carbs": "Carbs"
        case "fat": "Fat"
        default: id
        }
    }

    /// Decimals the square prints (board: Weight 80.2 kg; ACWR is a two-place ratio).
    public static func decimals(for id: String) -> Int {
        switch id {
        case "weight": 1
        case "acwr": 2
        default: 0
        }
    }

    /// B-57 W1: the square's icon (board EditToday).
    public static func systemImage(for id: String) -> String {
        switch id {
        case "hrv": "waveform.path.ecg"
        case "rhr": "heart"
        case "sleep": "moon"
        case "steps": "figure.walk"
        case "acwr": "bolt"
        case "protein": "fork.knife"
        case "kcal": "flame"
        case "weight": "scalemass"
        case "body_battery": "battery.75percent"
        case "readiness": "gauge.medium"
        case "carbs": "leaf"
        case "fat": "drop"
        default: "square"
        }
    }
}

/// RN `TodayTilePrefs`: `order` = ALL known ids in display order (hidden ones keep their last
/// position so re-showing restores it); `hidden` = subset of `order`, in `order` order.
public nonisolated struct TodayTilePrefs: Equatable, Sendable {
    public var order: [String]
    public var hidden: [String]

    public init(order: [String], hidden: [String]) {
        self.order = order
        self.hidden = hidden
    }

    /// The board's eight squares on Today; the W-FIX3 opt-in KPIs start hidden (My KPIs caps Today at 8).
    public static let `default` = TodayTilePrefs(order: TodayTileRegistry.ids, hidden: TodayTileRegistry.optInIds)

    /// RN `reconcile`: drop ids no longer registered, append (in registry order) any the blob
    /// predates, prune `hidden` to ids still in `order`. `order` is resolved with the same
    /// `resolveTileOrder` `TodayGrid` uses, so both screens agree on a stale blob.
    public static func reconcile(order: [String]?, hidden: [String]?) -> TodayTilePrefs {
        guard order != nil || hidden != nil else { return .default }
        let resolved = resolveTileOrder(chipIDs: TodayTileRegistry.ids, savedOrder: order)
        // W-FIX3: an opt-in square the stored order predates is appended hidden.
        let known = Set(order ?? [])
        let hiddenSet = Set(hidden ?? []).union(TodayTileRegistry.optInIds.filter { !known.contains($0) })
        return TodayTilePrefs(order: resolved, hidden: resolved.filter { hiddenSet.contains($0) })
    }
}

/// RN `visibleTodayTileOrder`.
public nonisolated func visibleTodayTileOrder(_ prefs: TodayTilePrefs) -> [String] {
    let hiddenSet = Set(prefs.hidden)
    return prefs.order.filter { !hiddenSet.contains($0) }
}

/// RN `moveTodayTile`: one slot earlier (-1) or later (+1); a no-op at either end / unknown id.
public nonisolated func moveTodayTile(_ prefs: TodayTilePrefs, id: String, direction: Int) -> TodayTilePrefs {
    guard let idx = prefs.order.firstIndex(of: id) else { return prefs }
    let swapIdx = idx + direction
    guard swapIdx >= 0, swapIdx < prefs.order.count else { return prefs }
    var order = prefs.order
    order.swapAt(idx, swapIdx)
    return TodayTilePrefs(order: order, hidden: prefs.hidden)
}

/// RN `setTodayTileHidden`: `hidden` stays filtered from `order` (never pushed to the end), so
/// toggling visibility never moves a tile — only reordering does.
public nonisolated func setTodayTileHidden(_ prefs: TodayTilePrefs, id: String, hide: Bool) -> TodayTilePrefs {
    var hiddenSet = Set(prefs.hidden)
    if hide { hiddenSet.insert(id) } else { hiddenSet.remove(id) }
    return TodayTilePrefs(order: prefs.order, hidden: prefs.order.filter { hiddenSet.contains($0) })
}

/// RN `reorderTodayTiles`: merges a reordered VISIBLE sequence back into the full order — hidden
/// tiles keep their exact slots, visible slots are filled from `newVisibleOrder` in sequence.
/// `newVisibleOrder` must be a permutation of `visibleTodayTileOrder(prefs)` (caller contract).
public nonisolated func reorderTodayTiles(_ prefs: TodayTilePrefs, newVisibleOrder: [String]) -> TodayTilePrefs {
    let hiddenSet = Set(prefs.hidden)
    var visibleIdx = 0
    let order = prefs.order.map { id -> String in
        if hiddenSet.contains(id) { return id }
        defer { visibleIdx += 1 }
        return newVisibleOrder[visibleIdx]
    }
    return TodayTilePrefs(order: order, hidden: prefs.hidden)
}

/// W-FIX3 C-a: the ONE selection (`KpiSelection.prefKey`, what My KPIs reads and writes) as
/// Today squares. Every registry id is a `KpiMetricId`, so the mapping is lossless.
public nonisolated func todayTilePrefs(from selection: KpiSelectionPrefs) -> TodayTilePrefs {
    let s = KpiSelection.reconcile(selection)
    return TodayTilePrefs.reconcile(order: s.order.map(\.rawValue), hidden: s.hidden.map(\.rawValue))
}

public nonisolated func kpiSelection(from tiles: TodayTilePrefs) -> KpiSelectionPrefs {
    KpiSelectionPrefs(order: tiles.order.compactMap(KpiMetricId.init(rawValue:)), hidden: tiles.hidden.compactMap(KpiMetricId.init(rawValue:)))
}

/// W-FIX3 C-a: Today's squares = My KPIs' "On Today". Once unified, the selection is read. The first
/// time (a pre-W-FIX3 install), EditToday's own set wins — it is what Today showed — and becomes the
/// selection; a fresh install seeds it with the board default. `prefs == nil` → the default.
public nonisolated func loadTodayTilePrefs(prefs: PrefStore?) -> TodayTilePrefs {
    guard let prefs else { return .default }
    if ((try? prefs.get(todayTilesUnifiedKey, as: Bool.self)) ?? nil) == true,
       let selection = (try? prefs.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)) ?? nil {
        return todayTilePrefs(from: selection)
    }
    let order = (try? prefs.get(todayTileOrderKey, as: [String].self)) ?? nil
    let hidden = (try? prefs.get(todayTileHiddenKey, as: [String].self)) ?? nil
    let tiles = TodayTilePrefs.reconcile(order: order, hidden: hidden)
    writeTodayTilePrefs(tiles, prefs: prefs)
    return tiles
}

/// Writes the one selection (and EditToday's own keys, kept for older readers) and tells Today.
/// No-op on nil/failed writes, never a crash.
public nonisolated func saveTodayTilePrefs(_ value: TodayTilePrefs, prefs: PrefStore?) {
    writeTodayTilePrefs(value, prefs: prefs)
    NotificationCenter.default.post(name: todayTilePrefsDidChange, object: nil)
}

private nonisolated func writeTodayTilePrefs(_ value: TodayTilePrefs, prefs: PrefStore?) {
    saveTileOrder(value.order, prefs: prefs)
    try? prefs?.set(todayTileHiddenKey, value.hidden)
    try? prefs?.set(KpiSelection.prefKey, kpiSelection(from: value))
    try? prefs?.set(todayTilesUnifiedKey, true)
}

/// W-FIX3 C-a: EditToday keeps My KPIs' limits (3…8 on Today) — the same `KpiSelection` rule.
public nonisolated func todayTileVisibilityAllowed(_ prefs: TodayTilePrefs, id: String, hide: Bool) -> Bool {
    guard prefs.hidden.contains(id) != hide else { return true }
    let shown = visibleTodayTileOrder(prefs).count
    return hide ? shown > KpiSelection.minSelected : shown < KpiSelection.maxSelected
}

// MARK: - B-57 W1 EditToday squares

/// One EditToday square carrying Today's own chip value (the board shows values). A real value
/// carries no status word in W1 (the normal is W3); a missing one is "— No data", or "— Not in
/// Health yet" when the source cannot supply it (rule 5: never a bare dash, never a zero).
public nonisolated func editTodaySquare(_ id: String, chips: [TodayChip], badge: JISquareBadge) -> JISquareItem {
    let chip = chips.first { $0.id == id }
    let value = chip?.value
    return JISquareItem(id: id, label: TodayTileRegistry.label(for: id), systemImage: TodayTileRegistry.systemImage(for: id),
                        tint: metricTintRole(id), value: value, decimals: TodayTileRegistry.decimals(for: id), unit: chip?.unit,
                        status: value == nil ? .missing(chip?.sourceMissing == true ? .notInHealthYet : .noData) : nil,
                        badge: badge)
}
public nonisolated func editTodayVisibleItems(_ prefs: TodayTilePrefs, chips: [TodayChip] = []) -> [JISquareItem] {
    visibleTodayTileOrder(prefs).map { editTodaySquare($0, chips: chips, badge: .hide) }
}
public nonisolated func editTodayHiddenItems(_ prefs: TodayTilePrefs, chips: [TodayChip] = []) -> [JISquareItem] {
    prefs.hidden.map { editTodaySquare($0, chips: chips, badge: .add) }
}
/// W-FIX2 BUG-20: the "Add a square" catalogue (board 04) — every square in EditToday's order,
/// ✓ when it is on Today, + when it is hidden.
public nonisolated func editTodayCatalogueItems(_ prefs: TodayTilePrefs, chips: [TodayChip] = []) -> [JISquareItem] {
    let hidden = Set(prefs.hidden)
    return prefs.order.map { editTodaySquare($0, chips: chips, badge: hidden.contains($0) ? .add : .selected) }
}
public nonisolated func editTodayCountText(_ prefs: TodayTilePrefs) -> String {
    "\(visibleTodayTileOrder(prefs).count) of \(prefs.order.count)"
}
