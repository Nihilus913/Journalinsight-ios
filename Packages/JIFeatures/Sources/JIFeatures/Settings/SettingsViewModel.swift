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
    /// W-FIX3 fixer C-e: builds a KPI's detail model for Settings → My KPIs square taps. nil =
    /// no hub provider → the squares stay display-only (never a tap that does nothing).
    public let makeKpiDetailModel: (@MainActor (KpiMetricId) -> KpiDetailViewModel?)?
    /// W-FIX3 fixer C-e: the KPI detail pushed over Settings → My KPIs; nil = none.
    public var kpiDetailMetric: KpiMetricId?
    /// Built once per tap (not per body pass), so the pushed detail keeps its loaded state.
    public private(set) var kpiDetailModel: KpiDetailViewModel?
    /// B-57 W1 r5: the goals document source the Weekly plan row seeds from — the same
    /// `EnergyProviding` the Nutrition-tab entry passes. nil = no hub provider (plan uses prefs).
    public let goalsProvider: (any EnergyProviding)?
    /// B-57 W1: Today's chips for EditToday's squares (App passes the live Today model's).
    public let todayChips: @MainActor () -> [TodayChip]
    /// Registered sections in render order (by `sortKey`, stable for equal keys).
    public let sections: [any SettingsSection]
    /// RN `saved` — "Using hub — saved." after a successful save; nil until then.
    public private(set) var savedMessage: String?

    /// B-57 W1 (g3): the board's "Sync now" row. App passes the real action (Apple Health upload,
    /// then the hub's `POST /api/v1/ingestion/sync` — the same `sync_all` job launchd runs); nil
    /// (previews, tests without it) = the row is not offered, never a button that does nothing.
    private let syncAction: (@MainActor () async throws -> Void)?
    private let now: () -> Date
    public private(set) var syncing = false
    public private(set) var syncFailed = false
    /// When this device last started a sync that the hub accepted.
    public private(set) var lastSyncStartedAt: Date?

    private let onSaved: (ConnectionConfig) -> Void

    public init(
        store: ConnectionConfigStore,
        prefs: PrefStore,
        backloadModel: HealthBackloadViewModel? = nil,
        healthPermissionModel: HealthPermissionViewModel? = nil,
        backupModel: BackupViewModel? = nil,
        goalsSetupModel: GoalsSetupViewModel? = nil,
        kpiListModel: KpiListViewModel? = nil,
        makeKpiDetailModel: (@MainActor (KpiMetricId) -> KpiDetailViewModel?)? = nil,
        goalsProvider: (any EnergyProviding)? = nil,
        todayChips: @escaping @MainActor () -> [TodayChip] = { [] },
        sections: [any SettingsSection] = SettingsRegistry.sections,
        syncAction: (@MainActor () async throws -> Void)? = nil,
        now: @escaping () -> Date = Date.init,
        onSaved: @escaping (ConnectionConfig) -> Void
    ) {
        self.syncAction = syncAction
        self.now = now
        self.connection = ConnectionSheetModel(store: store)
        self.prefs = prefs
        self.backloadModel = backloadModel
        self.healthPermissionModel = healthPermissionModel
        self.backupModel = backupModel
        self.goalsSetupModel = goalsSetupModel
        self.kpiListModel = kpiListModel
        self.makeKpiDetailModel = makeKpiDetailModel
        self.goalsProvider = goalsProvider
        self.todayChips = todayChips
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

    /// W-FIX3 fixer C-e: the `onSelectKpi` Settings hands `KpiListView` — a square tap pushes
    /// that KPI's detail. nil without a detail factory.
    public var kpiSelectAction: ((String) -> Void)? {
        guard makeKpiDetailModel != nil else { return nil }
        return { [weak self] raw in
            guard let metric = KpiMetricId(rawValue: raw) else { return }
            self?.kpiDetailModel = self?.makeKpiDetailModel?(metric)
            self?.kpiDetailMetric = metric
        }
    }

    public var canSyncNow: Bool { syncAction != nil }

    /// The newer of the hub's own last sync (from the connection test) and the last sync this
    /// device started. nil = unknown → the row shows "—".
    public var lastSyncDate: Date? {
        var hubLast: Date?
        if case .ok(let raw)? = connection.status, let raw { hubLast = parseHubTimestamp(raw) }
        return [hubLast, lastSyncStartedAt].compactMap { $0 }.max()
    }

    public func syncNow() async {
        guard let syncAction, !syncing else { return }
        syncing = true
        syncFailed = false
        let started = now()
        do {
            try await syncAction()
            lastSyncStartedAt = started
        } catch {
            syncFailed = true
        }
        syncing = false
    }

    /// RN `visibleKpiOrder(prefs).length` — reads W3b-L2's `KpiSelection.prefKey` so the subtitle
    /// matches what `KpiListView` shows.
    public var kpiSelectedCount: Int {
        let raw = try? prefs.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)
        return KpiSelection.visibleOrder(KpiSelection.reconcile(raw)).count
    }

    /// B-57 W1 r5: the Settings → Weekly plan entry's model — same store file as the Nutrition-tab
    /// entry and, when the hub speaks it, the same goals provider.
    public func makeWeeklyPlanModel() -> WeeklyPlanViewModel {
        // B-57 W2 (B-73): the user's own goals (`goals.macros`) seed the plan before the hub's.
        WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: prefs), goalsProvider: goalsProvider,
                            jiGoals: { [prefs] in try? MacroGoalsStore(prefs: prefs).load() })
    }

    public var kpiSubtitle: String { "\(kpiSelectedCount) selected · Today's stat strip and home-screen widget" }
}
