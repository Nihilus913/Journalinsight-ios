import Foundation
import HealthKit
import Observation
import JICore
import JIHub
import JIHealthKit
import JIPersistence
import JIFeatures
import JISnapshot
import JICompute
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
        // W-FIX7 F7-1: today's Apple Health workouts (session done) on every foreground.
        Task { @MainActor [weak self] in await self?.refreshTodayWorkouts() }
        guard !uploadInFlight, let uploader = healthKitUploader,
              !CommandLine.arguments.contains("-no-healthkit") else { return }
        uploadInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            await uploader.syncAll()
            await MainActor.run { self?.uploadInFlight = false }
        }
    }

    /// Toby 2026-10-01: Today's pull-to-refresh — Apple Health → hub, awaited, so the reload that
    /// follows already sees last night. Joins nothing if a foreground upload is running (that one
    /// sends the same data); `-no-healthkit` / no uploader → no-op.
    func uploadHealthNow() async {
        guard !uploadInFlight, let uploader = healthKitUploader,
              !CommandLine.arguments.contains("-no-healthkit") else { return }
        uploadInFlight = true
        await uploader.syncAll()
        uploadInFlight = false
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
    /// W-FIX6 F6-11 (S1): this connection's hub provider — the ONE source of the morning call,
    /// whichever data source (hub / on-device T2) the tiles read. nil = not connected.
    private(set) var hubProvider: (any HealthDataProvider)?

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
        installTodayWorkouts()
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
        hubProvider = provider
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
        // W-DATA fixer R3: the "Computed from these" tiles read the same sources as the screens that
        // show them — Sleep score = the hub's `/vitals/sleep-summary` `score_computed` (the Today
        // ring's source), Readiness = the hub's `/planning/morning` recovery (Decide's ring; W-FIX7
        // F7-3), else the recovery score over `/vitals/recovery-inputs`. Neither leaves "—".
        let provider = providerStore?.provider
        let window = RecoveryInsightService.windowDays
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
            },
            loadSleepScore: {
                guard let sp = provider as? any SleepSummaryProviding else { return nil }
                return try? await sp.sleepSummary().scoreComputed
            },
            loadReadiness: {
                // W-FIX7 fixer F7-3: the hub's recovery for today's call (Decide's ring, 36 on
                // 2026-09-28) first; the phone's own score only when the hub sent none.
                await healthReadinessLoad(
                    hubSignals: { try? await provider?.morning().gateSignals },
                    onDevice: {
                        guard let rp = provider as? any RecoveryInputsProviding else { return nil }
                        let day = RecoveryInsightService.localDayKey(Date())
                        // W-FIX10 R-04: the hub's calibration verdict rides along — "Calibrating", never a score.
                        guard let report = try? await rp.recoveryInputsReport(date: day, windowDays: window) else { return nil }
                        return RecoveryInsightService.score(days: report.days, today: day, calibration: report.calibration)
                    })
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
            // W-FIX2 FM-10: types with a hub column (dso-4 `resp_*`, `spo2_sleep_avg`, `vo2max`).
            // W-FIX10 DH-8: now `HKReadKind`s (the permission verdict reports them), so they ride
            // the read vocabulary — same types, metric names and version-1 anchors as when they
            // were named by identifier here (no re-send). SpO2 goes as HealthKit's 0–1 fraction
            // (the hub side scales it, like body fat).
            (.respiratoryRate, "respiratory_rate", "count/min", HKSampleMapping.perSample(unit: HKUnit(from: "count/min"))),
            (.oxygenSaturation, "blood_oxygen_saturation", "%", HKSampleMapping.perSample(unit: .percent())),
            // W-DATA R4: the night's sleeping wrist temperature (°C, one sample per night, dated at
            // its start; the hub moves it to the wake date and serves only the deviation from the
            // user's own baseline — `hae_bridge` `apple_sleeping_wrist_temperature`, migration 051).
            (.sleepingWristTemperature, "apple_sleeping_wrist_temperature", "degC", HKSampleMapping.perSample(unit: .degreeCelsius())),
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

    // MARK: - W-FIX7 F7-1: session done from Apple Health

    /// The shared today-workouts model Decide / Day / Training read (a seam for tests).
    @ObservationIgnored var todayWorkouts: TodayWorkoutsModel = .shared

    /// Points the model at Apple Health (`-no-healthkit` scripted runs: none, every session as it
    /// was) and republishes the glances when a workout lands, so the widget and the Live Activity
    /// say "done" without waiting for the next hub fetch.
    func installTodayWorkouts() {
        if todayWorkouts.source == nil, Self.readsHealthWorkouts(arguments: CommandLine.arguments,
                                                                 environment: ProcessInfo.processInfo.environment) {
            todayWorkouts.source = HKTodayWorkoutsReader(store: RealHealthStoreReader())
        }
        todayWorkouts.onChange = { [weak self] in self?.republishSnapshot() }
    }

    func refreshTodayWorkouts() async { await todayWorkouts.refresh() }

    /// W-FIX7 fixer: the real Health workouts reader is installed only in the app itself — never
    /// under `-no-healthkit`, never in a unit-test host (AppTests read the sim's real HealthKit
    /// through `TodayWorkoutsModel.shared` and failed whenever the sim held a workout today).
    static func readsHealthWorkouts(arguments: [String], environment: [String: String]) -> Bool {
        !arguments.contains("-no-healthkit") && environment["XCTestConfigurationFilePath"] == nil
    }

    /// W-FIX7 fixer F7-4: what a published snapshot does to the Live Activity. Nothing until the
    /// first Health workouts read has landed (`workoutsSettled`) — a relaunch that refreshed the
    /// activity before Health answered requested a new card, then ended it as "done" — one more
    /// "Done" card per relaunch. A done session finishes it; otherwise it is refreshed.
    enum LiveActivityStep: Equatable { case none, update, finish }

    static func liveActivityStep(_ snapshot: HubSnapshot, done: Bool, workoutsSettled: Bool) -> LiveActivityStep {
        guard drivesLiveActivity(snapshot), workoutsSettled else { return .none }
        return done ? .finish : .update
    }

    /// F7-1: the glance's session line — "Done · Traditional strength · 52 min · Bevel" once a
    /// matching workout is in Health today, else the call's own session.
    static func glanceSession(headlineSession: String?, completion: SessionCompletion) -> String {
        if completion.isDone, let done = completion.statusText { return done }
        return headlineSession ?? "No verdict yet"
    }

    /// F7-1: the Live Activity ends (showing "done") once today's session is done — never restarted
    /// for that day. Unit-test hosts get nil.
    @ObservationIgnored var liveActivityFinish: (@MainActor (HubSnapshot) -> Void)? = AppEnvironment.defaultLiveActivityFinish

    static var defaultLiveActivityFinish: (@MainActor (HubSnapshot) -> Void)? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return { @MainActor snapshot in LiveActivityController.shared.finish(from: snapshot) }
    }

    // MARK: - B-57 W5: glance extras (reason, plan, the user's cap, next session, signals)

    /// W3's recovery insight (owned by RootTabView) — read for the HRV/RHR normals on the glances.
    @ObservationIgnored weak var recoveryInsight: RecoveryInsightService?
    /// The week's plan progress for the glances. Set by RootTabView from the Training week model
    /// (B-52 cached plan sessions); nil = no week known, so the glances show no plan (never "0 of 4").
    @ObservationIgnored var glancePlan: (@MainActor () -> GlancePlan?)?

    /// W-FIX6 F6-11: the override in effect on this device (Decide's `VerdictOverrideViewModel.current`),
    /// set by RootTabView, so the glances show the call the user made — the same headline as Decide.
    @ObservationIgnored var currentOverride: (@MainActor () -> VerdictOverride?)?

    /// W-FIX6 F6-2: load the recovery insight (the glances' HRV/RHR normals) and republish, so a
    /// launch onto a tab that never mounts Recovery/Decide still gets its normals on the widget.
    func refreshGlanceInsight() async {
        await recoveryInsight?.refreshIfStale()
        republishSnapshot()
    }

    /// W-FIX5 W5-5: the verdict Live Activity, started (then refreshed) from the app on each
    /// published snapshot that carries a call. Unit-test hosts get nil (no real activity per test).
    @ObservationIgnored var liveActivity: (@MainActor (HubSnapshot) -> Void)? = AppEnvironment.defaultLiveActivity

    static var defaultLiveActivity: (@MainActor (HubSnapshot) -> Void)? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return { @MainActor snapshot in LiveActivityController.shared.update(from: snapshot) }
    }

    /// W-FIX5 W5-5: only a real call (a verdict date, a word other than "—") starts or refreshes the
    /// Live Activity — never an empty "No verdict yet" activity on the Lock Screen.
    static func drivesLiveActivity(_ snapshot: HubSnapshot) -> Bool {
        snapshot.verdictDate != nil && snapshot.verdictWord != "—" && !snapshot.verdictWord.isEmpty
    }

    /// Re-publish after something outside Today/Recovery changed (the HR cap, a weekday
    /// assignment) so the widgets' cap and plan ring follow without waiting for the next fetch.
    func republishSnapshot() {
        guard boundToday != nil || boundRecovery != nil else { return }
        publishSnapshot(today: boundToday, recovery: boundRecovery)
    }

    /// W-B57-W5 PF-04: the glances' sync moment is the one sync-pill rule (`TodayViewModel.syncedAt`
    /// — the newer of the hub's last sync and the last HealthKit upload 2xx), never a fetch time.
    static func glanceLastSync(today: TodayViewModel?) -> Date? { today?.syncedAt }

    /// W-B57-W5 fixer (glance-RHR): the gate never sends RHR, so the glance takes Recovery's latest
    /// RHR — the RHR KPI's own number — when it is from the verdict's night (that day or the one
    /// before). Older = left out, never an old number shown as this morning's.
    static func glanceLatestReadings(today: TodayViewModel?, asOf day: String) -> [String: Double] {
        guard let hit = KpiMetrics.latest(for: .rhr, recovery: today?.recovery ?? [], nutrition: [], dailyRows: [], gateAverages: nil),
              let asOf = isoFormatter.date(from: String(day.prefix(10))),
              let floor = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: asOf),
              hit.date >= isoFormatter.string(from: floor) else { return [:] }
        return ["rhr": hit.value]
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoDay(_ date: Date) -> String { String(date.ISO8601Format().prefix(10)) }

    private func publishSnapshot(today: TodayViewModel?, recovery: RecoveryViewModel?) {
        // W-FIX6 F6-11: Decide's own headline (word, session, tone) — never the hub's raw word.
        let headline = today?.headline(override: currentOverride?() ?? today?.morning?.verdictOverride)
        let readiness = today?.readiness ?? recovery?.latestReadiness
        let kpis = (today?.chips ?? []).map { SnapshotKPI(label: $0.label, value: $0.value, unit: $0.unit) }
        let lastSync = Self.glanceLastSync(today: today)
        let hrvNormal = recoveryInsight?.normal(for: .hrv)?.range
        let rhrNormal = recoveryInsight?.normal(for: .rhr)?.range
        let gateSignals = today?.morning?.gateSignals
        // W-B57-W5 fixer: the live Training week when RootTabView has one, else the cached B-52 plan.
        let plan = glancePlan?() ?? GlancePlan(TrainingViewModel.cachedWeekSummary(cache: cache, today: Self.isoDay(now()))?
            .applyingTodayWorkouts(TodayWorkout.merging(local: todayWorkouts.workouts, hub: today?.hubWorkouts ?? [])))
        // W-FIX7 F7-1: today's session against today's Apple Health workouts.
        let completion = today.map { $0.sessionCompletion(workouts: todayWorkouts, sessionLabel: headline?.session) } ?? .none
        let allKpis = Self.allKpis(today: today, cache: cache, hrvNormal: hrvNormal, rhrNormal: rhrNormal)
        let snapshot = HubSnapshot(
            verdictWord: headline?.word ?? "—",
            verdictSession: Self.glanceSession(headlineSession: headline?.session, completion: completion),
            verdictTone: Self.toneString(headline?.tone),
            verdictDate: today?.morning?.verdictDate,
            readiness: readiness,
            kpis: kpis,
            allKpis: allKpis,
            fetchedAt: now(),
            lastSync: lastSync,
            macros: currentMacrosSnapshot(),
            reason: HubSnapshot.reasonLine(from: gateSignals),
            planDone: plan?.total.flatMap { $0 > 0 ? plan?.done : nil },
            planTotal: plan?.total.flatMap { $0 > 0 ? $0 : nil },
            hrCap: GateSettingsStore(prefs: prefs).load().hrCapBpm,   // as stored; nil = no cap (no fallback)
            nextSession: plan?.next,
            signals: GlanceSignals.make(gateSignals: gateSignals, hrvNormal: hrvNormal, rhrNormal: rhrNormal,
                                        sleepGoalH: TargetsStore(prefs: prefs).load().goal(.sleep),   // W-TGT: the user's goal, nil until typed
                                        latest: Self.glanceLatestReadings(today: today, asOf: today?.morning?.verdictDate ?? Self.isoDay(now())))
        )
        snapshotStore.write(snapshot)
        // F7-1: a done session ends the Live Activity (with "done" on it) instead of refreshing it.
        switch Self.liveActivityStep(snapshot, done: completion.isDone, workoutsSettled: todayWorkouts.isSettled) {
        case .finish: liveActivityFinish?(snapshot)
        case .update: liveActivity?(snapshot)
        case .none: break
        }
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
    private static func allKpis(today: TodayViewModel?, cache: OfflineCache,
                                hrvNormal: ClosedRange<Double>?, rhrNormal: ClosedRange<Double>?) -> [SnapshotKPI] {
        let recovery = today?.recovery ?? []
        let dailyRows = today?.gate?.daily ?? []
        let averages = today?.gate?.averages
        let nutrition = (try? cache.get(KpiListViewModel.nutritionCacheKey, as: [NutritionDailyRow].self))?.value ?? []
        return KpiMetricId.allCases.map { id in
            let def = KpiMetrics.def(id)
            let value = KpiMetrics.latest(for: id, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows, gateAverages: averages)?.value
            // B-57 W5: the personal normal (W3) for the KpiWidget small band; none = "Calibrating".
            let normal: ClosedRange<Double>? = id == .hrv ? hrvNormal : (id == .rhr ? rhrNormal : nil)
            return SnapshotKPI(id: id, label: def.label, value: value, unit: def.unit.isEmpty ? nil : def.unit,
                               normalLow: normal?.lowerBound, normalHigh: normal?.upperBound)
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

/// B-57 W5: the week's strength plan for the glances — done / total this week and the next
/// session label ("Fri · Day 3 Full Upper"). Built by RootTabView from the Training week model.
struct GlancePlan: Equatable {
    var done: Int?
    var total: Int?
    var next: String?

    init(done: Int?, total: Int?, next: String?) {
        self.done = done; self.total = total; self.next = next
    }

    /// The glance fields of a Training week (nil = no week known → no plan on the glances).
    init?(_ week: TrainingWeekSummary?) {
        guard let week else { return nil }
        self.init(done: week.planDone, total: week.planTotal, next: week.nextSessionLabel)
    }
}

/// B-57 W2 (B-73): JIHealthKit's `HKDailyTotalsReader` rows as JICore `HealthDailyTotals` (a
/// field-for-field copy), so JIFeatures' `EnergyBandService` never imports HealthKit.
/// W-FIX7 N-1 / N-2: + fibre and sugar; every successful read is published to `feed`, which
/// Fuel, Nutrition, Energy and the KPI screens read (Apple Health first, YAZIO only for the
/// days Health lacks) — one Health read per foreground, not one per screen.
struct HealthDailyTotalsAdapter: HealthDailyTotalsProviding {
    let reader: HKDailyTotalsReader
    var feed: HealthDailyTotalsFeed = .shared
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals] {
        let rows = try await reader.dailyRows(days: days).map {
            HealthDailyTotals(date: $0.date, basalKcal: $0.basalKcal, activeKcal: $0.activeKcal, dietaryKcal: $0.dietaryKcal,
                              proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG, fiberG: $0.fiberG, sugarG: $0.sugarG)
        }
        let feed = self.feed
        await MainActor.run { feed.publish(rows) }
        return rows
    }
}
