import Foundation
import Observation
import JICore
import JIHub
import JIPersistence
import JIFeatures
import JISnapshot

/// W2h (B-9) placeholder: satisfies `BackloadRunning` so the App target compiles on this branch
/// before JIHealthKit exists. The integrator swaps this default for `HealthKitBackloader`
/// (`JIHealthKit`, L2's package) at the `AppEnvironment.init` call site — this type itself is
/// never touched by that swap, only the default argument is.
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

    /// W2h (B-9): the HealthKit backload runner, injected here so JIFeatures (which builds the
    /// Settings UI against `BackloadRunning` only) never imports JIHealthKit. Defaults to
    /// `NoopBackloader` until the integrator swaps in `HealthKitBackloader` (`JIHealthKit`).
    let backload: any BackloadRunning

    init(
        secrets: any SecretStore = KeychainStore(),
        inMemory: Bool = false,
        snapshotStore: SnapshotStore = SnapshotStore(suiteName: "group.toby913.JournalInsight"),
        now: @escaping () -> Date = Date.init,
        backload: any BackloadRunning = NoopBackloader()
    ) throws {
        self.secrets = secrets
        cache = OfflineCache(db: inMemory ? try .inMemory() : try .cache())
        prefs = PrefStore(db: inMemory ? try .inMemory() : try .onDisk())
        self.snapshotStore = snapshotStore
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
        let provider = HubDataProvider(client: HubClient(config: config))
        if let store = providerStore { store.provider = provider } else { providerStore = ProviderStore(provider: provider) }
        needsConnection = false
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
