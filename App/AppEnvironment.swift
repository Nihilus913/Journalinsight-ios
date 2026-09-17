import Foundation
import HealthKit
import Observation
import JICore
import JIHub
import JIHealthKit
import JIPersistence
import JIFeatures
import JISnapshot

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

    /// W2i (B-11): App-Group `UserDefaults` handed to `HealthBackloadViewModel` for the
    /// `hk.backload.writeHRV` toggle — same suite `SnapshotStore` uses, so JIHealthKit (L3) reads
    /// the same key this writes. Exposed (not just a VM-internal default) so `RootTabView` wires
    /// it explicitly and tests can substitute a scratch suite via `init(hrvPrefs:)`.
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

    func boot() throws {
        if let config = try ConnectionConfigStore(secrets: secrets).load() { apply(config) } else { needsConnection = true }
    }

    /// The hub is the only runtime provider. MockDataProvider is previews/tests only (spec §4.2).
    func apply(_ config: ConnectionConfig) {
        if let previous = activeBaseURL, previous != config.baseURL {
            try? cache.clear()
        }
        activeBaseURL = config.baseURL
        let hubClient = HubClient(config: config)
        let provider = HubDataProvider(client: hubClient)
        if let store = providerStore { store.provider = provider } else { providerStore = ProviderStore(provider: provider) }
        backload = HealthKitBackloader(hub: BackloadClient(hub: hubClient))
        let uploader = HealthKitUploader(store: RealHealthStoreReader(), hub: hubClient, specs: Self.healthKitUploadSpecs)
        healthKitUploader = uploader
        needsConnection = false
        // Fire-and-forget: permission UI (L3, `HealthPermissionView`) is the surface that asks
        // for read access explicitly; this best-effort call only starts delivery when access was
        // already granted in an earlier session (`requestAuthorization` on an already-decided
        // read type is a no-op per HealthKit, not a re-prompt).
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
    /// for an observer to fire. JIFeatures has its own `HKPermission` (no JIHealthKit import), so
    /// the two same-named enums are mapped explicitly here.
    func makeHealthPermissionModel() -> HealthPermissionViewModel {
        HealthPermissionViewModel(
            permission: Self.featurePermission(aggregateReadPermission()),
            appleWatchCapabilities: DataCapability.appleWatchCapabilities,
            requestPermission: { [weak self] in
                guard let self else { return .notDetermined }
                try? await self.healthPermissions.requestAuthorization()
                let status = await MainActor.run { self.aggregateReadPermission() }
                if status == .granted, let uploader = await MainActor.run(body: { self.healthKitUploader }) {
                    if let observers = try? await uploader.startBackgroundDelivery() {
                        await MainActor.run { self.healthKitObservers = observers }
                    }
                    await uploader.syncAll()
                }
                return Self.featurePermission(status)
            }
        )
    }

    /// One verdict over every available read kind: any `.denied` wins, then `.granted` only when
    /// all are granted, else `.notDetermined` (never asked, or asked and HealthKit hides the answer).
    private func aggregateReadPermission() -> JIHealthKit.HKPermission {
        let statuses = HKReadKind.availableCases.map { healthPermissions.status(for: $0) }
        if statuses.contains(.denied) { return .denied }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .granted }) { return .granted }
        return .notDetermined
    }

    private static func featurePermission(_ p: JIHealthKit.HKPermission) -> JIFeatures.HKPermission {
        switch p {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    /// W2d (L2) read-path metric specs — maps each Apple Watch sample type this app reads to the
    /// Health-Auto-Export metric name/units the hub's `hae_router.py` understands (frozen
    /// contract, W2d card). Built HERE rather than in `JIHealthKit` so
    /// `HKQuantityTypeIdentifier`/`HKCategoryTypeIdentifier` construction stays out of
    /// `JIHealthKit/Sources`, matching L1's identifier-isolation rule for that package (this file
    /// is outside that grep's scope). L1's `HKTypes`/`appleWatchCapabilities` may supersede this
    /// list once merged — the fixer aligns at integration.
    private static var healthKitUploadSpecs: [HKMetricSpec] {
        [
            HKMetricSpec(sampleType: HKQuantityType(.stepCount), metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count())),
            HKMetricSpec(sampleType: HKQuantityType(.activeEnergyBurned), metricName: HAEMetricName.activeEnergy, units: "kcal", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .kilocalorie())),
            HKMetricSpec(sampleType: HKQuantityType(.appleExerciseTime), metricName: HAEMetricName.exerciseTime, units: "min", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .minute())),
            HKMetricSpec(sampleType: HKQuantityType(.restingHeartRate), metricName: HAEMetricName.restingHeartRate, units: "bpm", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: HKUnit(from: "count/min"))),
            HKMetricSpec(sampleType: HKQuantityType(.heartRateVariabilitySDNN), metricName: HAEMetricName.heartRateVariability, units: "ms", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .secondUnit(with: .milli))),
            HKMetricSpec(sampleType: HKCategoryType(.sleepAnalysis), metricName: HAEMetricName.sleepAnalysis, units: "hr", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.sleepAnalysis()),
            HKMetricSpec(sampleType: HKQuantityType(.bodyMass), metricName: HAEMetricName.weightBodyMass, units: "kg", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .gramUnit(with: .kilo))),
        ]
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
    private func publishSnapshot(today: TodayViewModel?, recovery: RecoveryViewModel?) {
        let verdict = today?.verdict
        let readiness = today?.readiness ?? recovery?.latestReadiness
        let kpis = (today?.chips ?? []).map { SnapshotKPI(label: $0.label, value: $0.value, unit: $0.unit) }
        let lastSync = [today?.fetchedAt, recovery?.fetchedAt].compactMap { $0 }.max()
        let snapshot = HubSnapshot(
            verdictWord: verdict?.word ?? "—",
            verdictSession: verdict?.session ?? "No verdict yet",
            verdictTone: Self.toneString(verdict?.tone),
            verdictDate: today?.morning?.verdictDate,
            readiness: readiness,
            kpis: kpis,
            fetchedAt: now(),
            lastSync: lastSync
        )
        snapshotStore.write(snapshot)
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
