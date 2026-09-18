import Foundation
import Observation
import JICore
import JIHub
import JIPersistence

// W5a-L0 (P-settings seam). FROZEN after L0. Mirrors the state `mobile/app/settings.tsx` keeps
// (`baseURL`/`token`/`test`/`saved`, the `kpiSelectedCount` subtitle) and carries every model a
// registered section may need — sections read this object from the SwiftUI environment
// (`@Environment(SettingsViewModel.self)`), so a lane never has to thread a dependency through
// `SettingsView`. `prefs` is the on-device `PrefStore` every W5a screen persists through.
@Observable @MainActor
public final class SettingsViewModel {
    /// Hub fields + test — the same model `ConnectionSheet` (pre-connection sheet) uses.
    public let connection: ConnectionSheetModel
    public let prefs: PrefStore
    /// Optional (W2h, B-9): nil hides the Apple Health backload section.
    public let backloadModel: HealthBackloadViewModel?
    /// Optional (W2d): nil hides the Apple Watch (read) section.
    public let healthPermissionModel: HealthPermissionViewModel?
    /// Optional (W4-L4): nil = vault not unlocked yet → the row explains itself (rule 5).
    public let backupModel: BackupViewModel?
    /// Optional (W4-L3): nil = no hub provider that speaks `GoalsSetupProviding`.
    public let goalsSetupModel: GoalsSetupViewModel?
    /// Optional (W3b-L2): nil = no hub provider for the KPI list.
    public let kpiListModel: KpiListViewModel?
    /// Registered sections in render order (by `sortKey`, stable for equal keys).
    public let sections: [any SettingsSection]
    /// RN `saved` — "Using hub — saved." after a successful save; nil until then.
    public private(set) var savedMessage: String?

    private let onSaved: (ConnectionConfig) -> Void

    public init(
        store: ConnectionConfigStore,
        prefs: PrefStore,
        backloadModel: HealthBackloadViewModel? = nil,
        healthPermissionModel: HealthPermissionViewModel? = nil,
        backupModel: BackupViewModel? = nil,
        goalsSetupModel: GoalsSetupViewModel? = nil,
        kpiListModel: KpiListViewModel? = nil,
        sections: [any SettingsSection] = SettingsRegistry.sections,
        onSaved: @escaping (ConnectionConfig) -> Void
    ) {
        self.connection = ConnectionSheetModel(store: store)
        self.prefs = prefs
        self.backloadModel = backloadModel
        self.healthPermissionModel = healthPermissionModel
        self.backupModel = backupModel
        self.goalsSetupModel = goalsSetupModel
        self.kpiListModel = kpiListModel
        // `sorted` is stable in Swift's stdlib (documented since 5.x), so equal keys keep registry order.
        self.sections = sections.sorted { $0.sortKey < $1.sortKey }
        self.onSaved = onSaved
    }

    /// RN `useHub()`: persist, hand the config to the app (which rebuilds the provider), report.
    /// Returns false when `ConnectionSheetModel.save()` refused — its `saveError` says why.
    @discardableResult
    public func saveHub() -> Bool {
        guard let config = connection.save() else { return false }
        onSaved(config)
        savedMessage = "Using hub — saved."
        return true
    }

    /// RN `visibleKpiOrder(prefs).length` — reads W3b-L2's `KpiSelection.prefKey` so the subtitle
    /// matches what `KpiListView` shows.
    public var kpiSelectedCount: Int {
        let raw = try? prefs.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)
        return KpiSelection.visibleOrder(KpiSelection.reconcile(raw)).count
    }

    public var kpiSubtitle: String { "\(kpiSelectedCount) selected · Today's stat strip and home-screen widget" }
}
