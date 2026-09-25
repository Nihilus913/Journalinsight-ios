import Foundation
import Observation
import JIDesign
import JIPersistence

// W5a-L3 (P-edit-today). Port of `mobile/app/edit-today.tsx`'s state: every arrow/eye tap applies
// on top of the CURRENT prefs (functional updater, so fast repeat presses never collapse into
// one net move) and writes through immediately — no separate Save button (matches RN's local-prefs
// screens). MainActor by JIFeatures' default isolation.
@Observable
public final class EditTodayViewModel {
    public private(set) var prefs: TodayTilePrefs = .default
    private let store: PrefStore?

    /// Today's chips (value, unit, source support) so each square shows what Today shows.
    /// Empty = no Today data reached this screen; every square then says "— No data".
    public let chips: [TodayChip]

    public init(prefs: PrefStore?, chips: [TodayChip] = []) { self.store = prefs; self.chips = chips }

    public var visibleOrder: [String] { visibleTodayTileOrder(prefs) }

    public func load() { prefs = loadTodayTilePrefs(prefs: store); pageName = loadTodayPageName(prefs: store) }

    public func isHidden(_ id: String) -> Bool { prefs.hidden.contains(id) }

    /// RN `atTop` / `atBottom` — the arrow's `disabled` state.
    public func canMove(_ id: String, direction: Int) -> Bool {
        guard let idx = prefs.order.firstIndex(of: id) else { return false }
        let target = idx + direction
        return target >= 0 && target < prefs.order.count
    }

    public func move(_ id: String, direction: Int) {
        commit(moveTodayTile(prefs, id: id, direction: direction))
    }

    /// W-FIX3 C-a: refused past My KPIs' limits (at least 3, at most 8 squares on Today).
    public func setHidden(_ id: String, hide: Bool) {
        guard todayTileVisibilityAllowed(prefs, id: id, hide: hide) else { return }
        commit(setTodayTileHidden(prefs, id: id, hide: hide))
    }

    public private(set) var pageName: String = todayPageNameDefault

    /// W-FIX2 BUG-20: the "Add a square" catalogue (board 04) the dashed Add square opens. It lists
    /// every square — ✓ = on Today (tap removes), + = hidden (tap adds) — so Add always does something.
    public var showsAddCatalogue = false
    public func openAddCatalogue() { showsAddCatalogue = true }
    public func toggleFromCatalogue(_ id: String) { setHidden(id, hide: !isHidden(id)) }

    public func setPageName(_ raw: String) {
        pageName = normalizedTodayPageName(raw)
        saveTodayPageName(pageName, prefs: store)
    }

    /// B-57 W1 drag: `moving` lands before `target` inside the VISIBLE order; hidden slots keep.
    public func moveSquare(_ moving: String, before target: String) {
        let next = squareGridMove(visibleOrder, moving: moving, before: target)
        commit(reorderTodayTiles(prefs, newVisibleOrder: next))
    }

    private func commit(_ next: TodayTilePrefs) {
        guard next != prefs else { return }
        prefs = next
        saveTodayTilePrefs(next, prefs: store)
    }
}
