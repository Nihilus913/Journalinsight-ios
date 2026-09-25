import Foundation
import HealthKit
import Observation
import JICore
import JIHub
import JIHealthKit
import JIPersistence
import JIFeatures
import JISnapshot
#if canImport(WidgetKit)
import WidgetKit
#endif

/// W2h (B-9) fallback: satisfies `BackloadRunning` until a hub connection exists (no `HubClient`
/// to build a `BackloadClient`/`HealthKitBackloader` from yet). `apply(_:)` swaps this out for a
/// real `HealthKitBackloader` (`JIHealthKit`, L2's package) once a `ConnectionConfig` is known.
struct NoopBackloader: BackloadRunning {
    func authorize() async throws { throw BackloadError.healthDataUnavailable }
    func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
        throw BackloadError.healthDataUnavailable
    }
}

@Observable @MainActor
final class AppEnvironment {
    let secrets: any SecretStore
    let cache: OfflineCache
    let prefs: PrefStore
    var providerStore: ProviderStore?
    var needsConnection = false
    private var activeBaseURL: URL?

    /// P-snapshot-wiring (W2c-L1): App-Group-backed store the Watch app (L2) and Widgets/Live
    /// Activity (L3) read from. `suiteName` matches the App Group in
    /// `App/JournalInsight.entitlements` / `WatchApp/WatchApp.entitlements` /
    /// `Widgets/Widgets.entitlements`. Overridable so tests can inject a non-persistent
    /// `UserDefaults(suiteName:)` double instead of touching the real shared container.
    private let snapshotStore: SnapshotStore
    private let now: () -> Date

    /// App-Group `UserDefaults` handed to `HealthBackloadViewModel` — the same suite
    /// `SnapshotStore` uses, so the VM reads the backload cursor `HealthKitBackloader` (L3)
    /// writes. Exposed (not just a VM-internal default) so `RootTabView` wires it explicitly and
    /// tests can substitute a scratch suite via `init(hrvPrefs:)`. (Named for the HRV toggle it
    /// originally carried; that toggle went away with writer v4 — B-30.)
    let hrvPrefs: UserDefaults?

    /// W2h (B-9): the HealthKit backload runner, injected here so JIFeatures (which builds the
    /// Settings UI against `BackloadRunning` only) never imports JIHealthKit. `NoopBackloader`
    /// until `apply(_:)` has a `ConnectionConfig` to build a real `HealthKitBackloader` from.
    private(set) var backload: any BackloadRunning

    /// W2d (L2): the HealthKit read→hub uploader (dso 4, apple-health envelope). `nil` until
    /// `apply(_:)` has a `ConnectionConfig` to build a `HubClient` from — same lifecycle as
    /// `backload`. Retains the started `HKObserverQuery`s (`HKHealthStore` doesn't retain them
    /// itself) so background delivery keeps firing for the app's lifetime.
    private(set) var healthKitUploader: HealthKitUploader?
    private var healthKitObservers: [HKObserverQuery] = []
    /// B-65: guards `foregroundHealthUpload()` so a foreground bounce mid-upload doesn't stack runs.
    private var uploadInFlight = false

    /// B-65: uploads Apple Health on every foreground so last night's RMSSD + sleep segments reach
    /// the hub as soon as the app opens (background delivery alone can lag hours). Detached at
    /// `.utility`; a second call while one runs is a no-op. No uploader (no connection) or
    /// `-no-healthkit` (scripted sim runs) → nothing. Never prompts: `syncAll` only reads.
    func foregroundHealthUpload() {
        // B-73: recompute the plan band on the phone on every foreground, even while an upload is
        // in flight. Health read + local math only; it never talks to the hub (Review Focus 4).
        Task { @MainActor [weak self] in await self?.refreshEnergyBand() }
        guard !uploadInFlight, let uploader = healthKitUploader,
              !CommandLine.arguments.contains("-no-healthkit") else { return }
        uploadInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            await uploader.syncAll()
            await MainActor.run { self?.uploadInFlight = false }
        }
    }

    /// B-57 W1 r4 (g3): the Settings "Sync now" row. Sends Apple Health to the hub first (so last
    /// night is in), then asks the hub to run its canonical sync job (`POST /api/v1/ingestion/sync`
    /// — the same `sync_all` run launchd starts at 07:00; the hub never runs two at once). Throws
    /// when there is no hub or the hub refused, so the row can say "Failed".
    func syncNow() async throws {
        guard let client = activeHubClient else { throw HubError.network("No hub connection") }
        if let uploader = healthKitUploader, !CommandLine.arguments.contains("-no-healthkit") {
            await uploader.syncAll()
        }
        let _: [String: String] = try await client.post("/api/v1/ingestion/sync", body: [String: String]())
    }

    /// The hub client of the connection `apply(_:)` last installed (nil before one exists).
    private var activeHubClient: HubClient?

    /// W2d (L1): three-state read-permission model over the real `HKHealthStore`. Hub-independent,
    /// so it lives from `init` — `ConnectionSheet`'s "Apple Watch (read)" section (L3) is driven
    /// from it via `makeHealthPermissionModel()`.
    let healthPermissions = HealthKitPermissions(authorizer: HKHealthStore())

    init(
        secrets: any SecretStore = KeychainStore(),
        inMemory: Bool = false,
        snapshotStore: SnapshotStore = SnapshotStore(suiteName: "group.toby913.JournalInsight"),
        hrvPrefs: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight"),
        now: @escaping () -> Date = Date.init,
        backload: any BackloadRunning = NoopBackloader()
    ) throws {
        self.secrets = secrets
        cache = OfflineCache(db: inMemory ? try .inMemory() : try .cache())
        prefs = PrefStore(db: inMemory ? try .inMemory() : try .onDisk())
        self.snapshotStore = snapshotStore
        self.hrvPrefs = hrvPrefs
        self.now = now
        self.backload = backload
    }

    /// B-46 (L1) dev affordance: `-hub-url <url> -hub-token <token>` on the launch command line
    /// applies that connection before the persisted one is read, so a simulator run can be pointed
    /// at the live hub from `xcrun simctl launch` without driving the Connection sheet by hand.
    /// Only honoured in DEBUG builds; the release app always reads the Keychain config.
    static func launchArgumentConfig(_ arguments: [String] = CommandLine.arguments) -> ConnectionConfig? {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.index(after: i) < arguments.endIndex else { return nil }
            return arguments[arguments.index(after: i)]
        }
        guard let raw = value("-hub-url"), let url = URL(string: raw), let token = value("-hub-token") else { return nil }
        return ConnectionConfig(baseURL: url, token: token)
    }

    func boot() throws {
        // W8-L1 appWiring: warm the haptics prefs cache from disk at cold start, so
        // `JIHapticDispatcher.shared.prefs` reflects the persisted enabled/intensity values
        // immediately instead of the open default (enabled, 100) until Settings is visited.
        HapticsPrefsStore.warm(from: prefs)
        #if DEBUG
        if let injected = Self.launchArgumentConfig() {
            try? ConnectionConfigStore(secrets: secrets).save(injected)
            apply(injected)
            return
        }
        #endif
        if let config = try ConnectionConfigStore(secrets: secrets).load() { apply(config) } else { needsConnection = true }
    }

    /// The hub is the only runtime provider. MockDataProvider is previews/tests only (spec §4.2).
    func apply(_ config: ConnectionConfig) {
        if let previous = activeBaseURL, previous != config.baseURL {
            try? cache.clear()
        }
        activeBaseURL = config.baseURL
        let hubClient = HubClient(config: config)
        activeHubClient = hubClient
        let provider = HubDataProvider(client: hubClient)
        let store: ProviderStore
        if let existing = providerStore { existing.provider = provider; store = existing } else { store = ProviderStore(provider: provider); providerStore = store }
        // W7-L3 (P-healthkit-t2-provider): re-point the debug data-source switch at THIS
        // connection's hub provider and re-apply the persisted choice. Release builds always
        // land on the hub — see `JIFeatures.ProviderSwitch.install`.
        ProviderSelection.install(store: store, hub: provider, prefs: prefs)
        // W5b-L1 (P-data-quality) close-out wiring: the Data Quality screen (Settings row + the
        // Today freshness-badge tap) reads its provider from this seam; nil = honest "not wired".
        DataQualityAccess.shared.install(provider)
        backload = HealthKitBackloader(hub: BackloadClient(hub: hubClient))
        let uploader = HealthKitUploader(store: RealHealthStoreReader(), hub: hubClient, specs: Self.healthKitUploadSpecs)
        healthKitUploader = uploader
        needsConnection = false
        // Fire-and-forget: permission UI (L3, `HealthPermissionView`) is the surface that asks
        // for read access explicitly; this best-effort call only starts delivery when access was
        // already granted in an earlier session (`requestAuthorization` on an already-decided
        // read type is a no-op per HealthKit, not a re-prompt).
        // B-46 (L1): `-no-healthkit` suppresses the cold-start HealthKit prompt so a scripted
        // simulator run against the live hub lands on Today instead of the system access sheet.
        guard !CommandLine.arguments.contains("-no-healthkit") else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await uploader.requestAuthorization()
                let observers = try await uploader.startBackgroundDelivery()
                await MainActor.run { self.healthKitObservers = observers }
            } catch {
                // Denied/unavailable: L3's permission screen is the honest-copy surface for this;
                // nothing to surface from here.
            }
        }
    }

    /// W2d close-out wiring (L1 ↔ L2 ↔ L3 seam): the view model `ConnectionSheet` shows. Its
    /// request closure runs the real HealthKit sheet, then — on grant — starts L2's background
    /// delivery and one immediate `syncAll()` so the first upload lands as dso 4 without waiting
    /// for an observer to fire. `HKPermission` is JIHealthKit's on both sides since W8-L4 (B-12).
    func makeHealthPermissionModel() -> HealthPermissionViewModel {
        // `aggregateReadPermission()` is async (B-13 fix: it now calls HealthKit's
        // `getRequestStatusForAuthorization`, which has no synchronous form), so the model starts
        // at `.notDetermined` and `adopt(_:)`s the real status once the lookup returns — never a
        // guessed `.denied` in the meantime (rule 5: no false-confident state).
        let model = HealthPermissionViewModel(
            permission: .notDetermined,
            appleWatchCapabilities: DataCapability.appleWatchCapabilities,
            requestPermission: { [weak self] in
                guard let self else { return .notDetermined }
                try? await self.healthPermissions.requestAuthorization()
                let status = await self.aggregateReadPermission()
                // B-13 fix: start delivery/sync whenever the read isn't provably undetermined —
                // HealthKit never confirms a read grant beyond `.unnecessary`, so waiting for a
                // stricter signal than "not notDetermined" would never fire (root cause).
                if status != .notDetermined, let uploader = await MainActor.run(body: { self.healthKitUploader }) {
                    if let observers = try? await uploader.startBackgroundDelivery() {
                        await MainActor.run { self.healthKitObservers = observers }
                    }
                    // Never awaited here: the first sync can take minutes on a deep history, and the
                    // permission sheet's caller must return at once (2026-09-23 connect hang).
                    Task.detached(priority: .background) { await uploader.syncAll() }
                }
                return status
            }
        )
        Task { [weak self, weak model] in
            guard let self, let model else { return }
            let status = await self.aggregateReadPermission()
            model.adopt(status)
        }
        return model
    }

    /// One verdict over every available read kind: any `.denied` wins, then `.granted` only when
    /// all are granted, else `.notDetermined` (never asked, or asked and HealthKit hides the
    /// answer — see `JIHealthKit.HealthKitPermissions.status(for:)`, B-13). Sequential `await`s
    /// (not a task group) — `HKReadKind.availableCases` is a handful of kinds and this keeps the
    /// call off `self` from concurrent child tasks.
    private func aggregateReadPermission() async -> HKPermission {
        let permissions = healthPermissions
        var statuses: [HKPermission] = []
        for kind in HKReadKind.availableCases {
            statuses.append(await permissions.status(for: kind))
        }
        if statuses.contains(.denied) { return .denied }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .granted }) { return .granted }
        return .notDetermined
    }

    /// W2d (L2) read-path metric specs — maps each Apple Watch sample type this app reads to the
    /// Health-Auto-Export metric name/units the hub's `hae_router.py` understands (frozen
    /// contract, W2d card). W8-L4 (B-12): keyed by `HKReadKind` (JIHealthKit's single read
    /// vocabulary) instead of constructing `HKQuantityTypeIdentifier`s here a second time, so the
    /// upload set can never drift from the permission set. A kind whose type doesn't resolve on
    /// this OS (`sampleType == nil`) is skipped rather than crashed on. The W2d upload subset,
    /// native RMSSD (appended below) and, since W-FIX2 (FM-10), body composition, respiration,
    /// SpO2, basal energy and VO2max. Workouts stay out (B-70). Internal (not private) so
    /// `HealthKitUploadSpecsTests` can pin the list.
    static var healthKitUploadSpecs: [HKMetricSpec] {
        let specs: [(HKReadKind, String, String, @Sendable ([HKSample]) -> [HAEDataPoint])] = [
            (.stepCount, HAEMetricName.stepCount, "count", HKSampleMapping.perSample(unit: .count())),
            (.activeEnergy, HAEMetricName.activeEnergy, "kcal", HKSampleMapping.perSample(unit: .kilocalorie())),
            (.exerciseTime, HAEMetricName.exerciseTime, "min", HKSampleMapping.perSample(unit: .minute())),
            (.restingHeartRate, HAEMetricName.restingHeartRate, "bpm", HKSampleMapping.perSample(unit: HKUnit(from: "count/min"))),
            (.hrvSDNN, HAEMetricName.heartRateVariability, "ms", HKSampleMapping.perSample(unit: .secondUnit(with: .milli))),
            (.sleepAnalysis, HAEMetricName.sleepAnalysis, "hr", HKSampleMapping.sleepAnalysis()),
            (.bodyMass, HAEMetricName.weightBodyMass, "kg", HKSampleMapping.perSample(unit: .gramUnit(with: .kilo))),
            // W-FIX2 FM-10: read-authorized and mapped by the hub (`hae_bridge.py` body_fat_pct /
            // lean_mass_kg), but never uploaded since the HAE era (last row 07-23). Body fat goes as
            // HealthKit's 0–1 fraction; the hub scales ≤ 1 to percent.
            (.bodyFatPercentage, HAEMetricName.bodyFatPercentage, "%", HKSampleMapping.perSample(unit: .percent())),
            (.leanBodyMass, HAEMetricName.leanBodyMass, "kg", HKSampleMapping.perSample(unit: .gramUnit(with: .kilo))),
            (.bodyMassIndex, HAEMetricName.bodyMassIndex, "count", HKSampleMapping.perSample(unit: .count())),
            // B-57 W2 (A3): basal energy is an `HKReadKind` now (read for the on-phone energy
            // balance), so it moves here from the identifier list below — same type, metric name
            // and v1 anchor. The dietary kinds are read-only for the phone and never uploaded.
            (.basalEnergy, "basal_energy_burned", "kcal", HKSampleMapping.perSample(unit: .kilocalorie())),
        ]
        // W-FIX2 FM-10: types with a hub column (dso-4 `resp_*`, `spo2_sleep_avg`, `vo2max`,
        // all 14/14 null) that `HKReadKind` has no case for yet, so
        // they are named by identifier here. Health Auto Export metric names; SpO2 goes as
        // HealthKit's 0–1 fraction (the hub side scales it, like body fat).
        let extra: [(HKQuantityTypeIdentifier, String, String, @Sendable ([HKSample]) -> [HAEDataPoint])] = [
            (.respiratoryRate, "respiratory_rate", "count/min", HKSampleMapping.perSample(unit: HKUnit(from: "count/min"))),
            (.oxygenSaturation, "blood_oxygen_saturation", "%", HKSampleMapping.perSample(unit: .percent())),
            (.vo2Max, "vo2_max", "ml/(kg·min)", HKSampleMapping.perSample(unit: .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())))),
        ]
        // 2026-09-23 (end-to-end audit): native RMSSD (iOS/watchOS 27) was built and tested
        // (`appendingNativeRMSSD`, UploaderRMSSDTests) but never wired here, so the hub's
        // hrv_rmssd_ms stayed empty for the Apple Watch — the metric the Apple gate (B-65) needs.
        return (specs.compactMap { kind, metricName, units, mapSamples in
            guard let sampleType = kind.sampleType else { return nil }
            // B-65: v2 = one 120-day re-send so the hub gets sleep segments for the whole baseline window.
            let anchorVersion = kind == .sleepAnalysis ? 2 : 1
            return HKMetricSpec(sampleType: sampleType, metricName: metricName, units: units, backgroundFrequency: .hourly, anchorVersion: anchorVersion, mapSamples: mapSamples)
        } + extra.map { id, metricName, units, mapSamples in
            HKMetricSpec(sampleType: HKQuantityType(id), metricName: metricName, units: units, backgroundFrequency: .hourly, mapSamples: mapSamples)
        }).appendingNativeRMSSD()
    }

    /// P-snapshot-wiring (W2c-L1): wires both hub-backed view models' `onSectionUpdate` hooks
    /// (see their doc comments) to publish into `snapshotStore` — the App-Group `UserDefaults` the
    /// Watch glances (L2) and widgets/Live Activity (L3) read. `RootTabView` calls this once, right
    /// after it creates each fresh `TodayViewModel`/`RecoveryViewModel` pair (a hub switch in
    /// `ConnectionSheet` recreates both, so this is re-bound there too).
    ///
    /// `[weak self]` only — the closures are owned by the VMs, not by `self`, so there is no
    /// retain cycle to worry about the other way.
    func bind(today: TodayViewModel?, recovery: RecoveryViewModel?) {
        boundToday = today; boundRecovery = recovery
        // Either side may be nil: the tabs build their view models lazily, so this is called
        // after each construction and re-binds whichever pair exists at that moment.
        today?.onSectionUpdate = { [weak self, weak today, weak recovery] in
            guard let self, let today else { return }
            self.publishSnapshot(today: today, recovery: recovery)
        }
        recovery?.onSectionUpdate = { [weak self, weak today, weak recovery] in
            guard let self, let recovery else { return }
            self.publishSnapshot(today: today, recovery: recovery)
        }
    }

    /// Builds a `HubSnapshot` from whatever the two view models currently hold and writes it to
    /// the shared App Group — deliberately from their already-public, already-sanitized surface
    /// (`verdict`, `readiness`, `chips`, `fetchedAt`) rather than reaching into hub responses
    /// directly, so the connection token (never present on these VMs' public API) can't leak into
    /// the widget-facing snapshot even by accident.
    /// The pair `bind` last wired, so a band refresh can republish the widget macros.
    @ObservationIgnored private weak var boundToday: TodayViewModel?
    @ObservationIgnored private weak var boundRecovery: RecoveryViewModel?

    // MARK: - B-57 W2 (B-73): the user's nutrition goals + the phone's plan band

    /// The user's nutrition goals (`goals.macros`, unset until saved) over the same on-disk prefs DB.
    @ObservationIgnored lazy var macroGoals = MacroGoalsStore(prefs: prefs)
    /// Health totals + the user's target → plan band. Built once by `makeEnergyBand()`;
    /// `-no-healthkit` runs get a nil reader (cache only). It never pushes to the hub: the only
    /// hub push is the save-only goals mirror inside GoalsSetup (TEMP bridge until B-50).
    var energyBand: EnergyBandService?

    @discardableResult
    func makeEnergyBand() -> EnergyBandService {
        if let energyBand { return energyBand }
        let reader: (any HealthDailyTotalsProviding)? = CommandLine.arguments.contains("-no-healthkit")
            ? nil : HealthDailyTotalsAdapter(reader: HKDailyTotalsReader(store: RealHealthStoreReader()))
        let service = EnergyBandService(reader: reader, store: macroGoals, cache: cache)
        service.recompute()   // goals + cached totals before the first Health read lands
        energyBand = service
        return service
    }

    /// Foreground hook: re-read Health, recompute the band, republish the widget macros.
    func refreshEnergyBand() async {
        await makeEnergyBand().refresh()
        if let today = boundToday { publishSnapshot(today: today, recovery: boundRecovery) }
    }

    /// Macros left today for the widget, from the band service's Health totals. nil = no goal set
    /// or no Health food readable (the widget keeps its KPI face; never a default).
    func currentMacrosSnapshot() -> SnapshotMacros? {
        guard let band = energyBand else { return nil }
        let g = band.goals
        let t = band.today
        return SnapshotMacros.make(
            goals: (g?.targetKcal, g?.proteinG, g?.carbsG, g?.fatG),
            eatenToday: (t?.dietaryKcal, t?.proteinG, t?.carbsG, t?.fatG),
            healthReadable: band.totals.contains { $0.dietaryKcal != nil },
            asOf: band.fetchedAt
        )
    }

    private func publishSnapshot(today: TodayViewModel?, recovery: RecoveryViewModel?) {
        let verdict = today?.verdict
        let readiness = today?.readiness ?? recovery?.latestReadiness
        let kpis = (today?.chips ?? []).map { SnapshotKPI(label: $0.label, value: $0.value, unit: $0.unit) }
        let lastSync = [today?.fetchedAt, recovery?.fetchedAt].compactMap { $0 }.max()
        let allKpis = Self.allKpis(today: today, cache: cache)
        let snapshot = HubSnapshot(
            verdictWord: verdict?.word ?? "—",
            verdictSession: verdict?.session ?? "No verdict yet",
            verdictTone: Self.toneString(verdict?.tone),
            verdictDate: today?.morning?.verdictDate,
            readiness: readiness,
            kpis: kpis,
            allKpis: allKpis,
            fetchedAt: now(),
            lastSync: lastSync,
            macros: currentMacrosSnapshot()
        )
        snapshotStore.write(snapshot)
        // W-B34 (B-34): the widgets' timelines are `.never` — without this signal a placed widget
        // kept showing the snapshot it was first rendered with until iOS happened to refresh it.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// W-B34 (B-36): every KPI's latest value for the configurable KPI widget — one entry per
    /// `KpiMetricId.allCases`, computed by the same `KpiMetrics.latest(for:…)` the KPI screens use,
    /// over what `TodayViewModel` already holds (recovery, gate daily rows + averages). The four
    /// nutrition KPIs read the rows `KpiListViewModel` last cached under
    /// `KpiListViewModel.nutritionCacheKey` — never a fetch from here; no cache → nil ("—").
    private static func allKpis(today: TodayViewModel?, cache: OfflineCache) -> [SnapshotKPI] {
        let recovery = today?.recovery ?? []
        let dailyRows = today?.gate?.daily ?? []
        let averages = today?.gate?.averages
        let nutrition = (try? cache.get(KpiListViewModel.nutritionCacheKey, as: [NutritionDailyRow].self))?.value ?? []
        return KpiMetricId.allCases.map { id in
            let def = KpiMetrics.def(id)
            let value = KpiMetrics.latest(for: id, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows, gateAverages: averages)?.value
            return SnapshotKPI(id: id, label: def.label, value: value, unit: def.unit.isEmpty ? nil : def.unit)
        }
    }

    private static func toneString(_ tone: VerdictTone?) -> String {
        switch tone {
        case .go: "go"
        case .amber: "amber"
        case .red: "red"
        case .muted, .none: "muted"
        }
    }
}

/// B-57 W2 (B-73): JIHealthKit's `HKDailyTotalsReader` rows as JICore `HealthDailyTotals` (a
/// field-for-field copy), so JIFeatures' `EnergyBandService` never imports HealthKit.
struct HealthDailyTotalsAdapter: HealthDailyTotalsProviding {
    let reader: HKDailyTotalsReader
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals] {
        try await reader.dailyRows(days: days).map {
            HealthDailyTotals(date: $0.date, basalKcal: $0.basalKcal, activeKcal: $0.activeKcal, dietaryKcal: $0.dietaryKcal,
                              proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        }
    }
}
