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
        // W8-L1 appWiring: warm the haptics prefs cache from disk at cold start, so
        // `JIHapticDispatcher.shared.prefs` reflects the persisted enabled/intensity values
        // immediately instead of the open default (enabled, 100) until Settings is visited.
        HapticsPrefsStore.warm(from: prefs)
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
                    await uploader.syncAll()
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
    /// this OS (`sampleType == nil`) is skipped rather than crashed on. Still the W2d upload
    /// subset — no RMSSD/body-comp/workout upload, the hub has no HAE metric for those.
    private static var healthKitUploadSpecs: [HKMetricSpec] {
        let specs: [(HKReadKind, String, String, @Sendable ([HKSample]) -> [HAEDataPoint])] = [
            (.stepCount, HAEMetricName.stepCount, "count", HKSampleMapping.perSample(unit: .count())),
            (.activeEnergy, HAEMetricName.activeEnergy, "kcal", HKSampleMapping.perSample(unit: .kilocalorie())),
            (.exerciseTime, HAEMetricName.exerciseTime, "min", HKSampleMapping.perSample(unit: .minute())),
            (.restingHeartRate, HAEMetricName.restingHeartRate, "bpm", HKSampleMapping.perSample(unit: HKUnit(from: "count/min"))),
            (.hrvSDNN, HAEMetricName.heartRateVariability, "ms", HKSampleMapping.perSample(unit: .secondUnit(with: .milli))),
            (.sleepAnalysis, HAEMetricName.sleepAnalysis, "hr", HKSampleMapping.sleepAnalysis()),
            (.bodyMass, HAEMetricName.weightBodyMass, "kg", HKSampleMapping.perSample(unit: .gramUnit(with: .kilo))),
        ]
        return specs.compactMap { kind, metricName, units, mapSamples in
            guard let sampleType = kind.sampleType else { return nil }
            return HKMetricSpec(sampleType: sampleType, metricName: metricName, units: units, backgroundFrequency: .hourly, mapSamples: mapSamples)
        }
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
