import Foundation
import Observation
import JIPersistence

// W5a-L3 (P-edit-today). Port of `mobile/app/edit-today.tsx`'s state: every arrow/eye tap applies
// on top of the CURRENT prefs (functional updater, so fast repeat presses never collapse into
// one net move) and writes through immediately — no separate Save button (matches RN's local-prefs
// screens). MainActor by JIFeatures' default isolation.
@Observable
public final class EditTodayViewModel {
    public private(set) var prefs: TodayTilePrefs = .default
    private let store: PrefStore?

    public init(prefs: PrefStore?) { self.store = prefs }

    public var visibleOrder: [String] { visibleTodayTileOrder(prefs) }

    public func load() { prefs = loadTodayTilePrefs(prefs: store) }

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

    public func setHidden(_ id: String, hide: Bool) {
        commit(setTodayTileHidden(prefs, id: id, hide: hide))
    }

    private func commit(_ next: TodayTilePrefs) {
        guard next != prefs else { return }
        prefs = next
        saveTodayTilePrefs(next, prefs: store)
    }
}
