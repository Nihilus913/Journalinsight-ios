#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// Why a T2 (on-device) provider refused a call.
///
/// Distinct from `HubError` on purpose: nothing here is a network condition, so the UI must not
/// offer "retry" — the honest copy is "not available on Apple Watch" (XC `CLAUDE.md` rule 5).
public enum ProviderError: Error, Equatable, Sendable {
    /// The provider cannot serve this domain. The payload is the `DataCapability` the caller
    /// should have checked on `provider.capabilities` first.
    case notCapable(DataCapability)
    /// HealthKit itself is unavailable on this device (iPad, Mac, simulator without Health).
    case healthDataUnavailable
}

/// **T2**: the Apple-only provider — the app computes from HealthKit on this device instead of
/// asking the Mac hub (T1, `JIHub.HubDataProvider`). Spec §4.2's capability seam is what makes the
/// two interchangeable: every tile reads `capabilities`, never the provider type.
///
/// ## The gate is deliberately OFF
/// `gate`, `morning` and `morningVerdict` always throw `ProviderError.notCapable(.gate)`, even
/// though `DataCapability.appleWatchCapabilities` (frozen, `Capabilities+HK.swift`) lists those
/// domains. The verdict is not a formula over today's numbers alone — it is a comparison against a
/// **per-source median + MAD baseline** (memory `project_source_agnostic_gate`: Apple and Garmin
/// readings do not align, so a Garmin-fitted baseline applied to Apple numbers produces a
/// confidently wrong verdict). That baseline store is not ported yet; the spec's risk table
/// (`2026-09-12-ji-swift-native-migration-design.md` L276) gates T2's verdict behind an
/// overnight-equivalence proof. `docs/BACKLOG.md`: "T2 baseline store median+MAD after
/// overnight-equivalence proof" — flip these three methods on there, not here.
///
/// `@unchecked Sendable`: the only mutable state is `anchors`/`lastAnchorFetch`, guarded by
/// `lock` on every access; everything else is a `let`.
public final class HealthKitProvider: HealthDataProvider, @unchecked Sendable {
    private let store: any HealthStoreReading
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    /// Latest `HKQueryAnchor` per sample-type identifier, kept so `syncStatus()` can report a real
    /// last-fetch and a future incremental path has somewhere to resume from.
    private var anchors: [String: HKQueryAnchor] = [:]
    private var lastAnchorFetch: Date?

    /// What this provider supplies. Defaults to the frozen `appleWatchCapabilities` bitmap;
    /// injectable so a test can drive the "capability absent → `notCapable`" table without
    /// touching the frozen extension.
    public let capabilities: DataCapability

    public init(
        store: any HealthStoreReading,
        capabilities: DataCapability = .appleWatchCapabilities,
        calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = .current
            return c
        }(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.capabilities = capabilities
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Health

    /// There is no endpoint to probe on device, so "healthy" means HealthKit is usable here.
    /// Reported, never thrown, so the hub watchdog and the Today staleness banner can render the
    /// same honest string for both providers.
    public func health() async throws -> HealthResponse {
        HealthResponse(status: store.isHealthDataAvailable ? "ok" : "unavailable")
    }

    // MARK: - Capability-gated OFF (see the type's doc comment)

    public func gate(windowDays: Int) async throws -> GateResponse {
        throw ProviderError.notCapable(.gate)
    }

    public func morning() async throws -> MorningResponse {
        throw ProviderError.notCapable(.gate)
    }

    public func morningVerdict(date: String) async throws -> MorningVerdict {
        throw ProviderError.notCapable(.gate)
    }

    // MARK: - Recovery

    /// Resting HR + HRV + sleep for the last `windowDays` local days, assembled into the hub's own
    /// `RecoveryDay` shape. The sleep score comes from `JICompute.computeSleepScore` (W6 parity
    /// port) via `HKSleepNight` — this package holds no sleep-score arithmetic of its own.
    ///
    /// Body Battery, training readiness and the Garmin sleep score stay `nil`: HealthKit cannot
    /// supply them and `appleWatchCapabilities` never claims them.
    public func recovery(windowDays: Int = 28) async throws -> [RecoveryDay] {
        try require(.recovery)
        try requireHealthData()
        let window = HKSampleWindow(windowDays: windowDays, now: now(), calendar: calendar)
        let rhr = try await samples(for: .restingHeartRate)
        let hrv: [HKSample] = if let kind = hrvKind { try await samples(for: kind) } else { [] }
        let sleep = capabilities.contains(.sleepSummary) ? try await samples(for: .sleepAnalysis) : []
        return HKRecoveryAssembler.days(window: window, restingHeartRate: rhr, hrv: hrv, sleep: sleep)
    }

    /// Which HRV type this provider reads. Native RMSSD (iOS 27, memory
    /// `reference_apple_readiness_app`) whenever the capability is claimed **and** the running OS
    /// actually exposes the type — `HKReadKind.hrvRMSSD.sampleType` is `nil` otherwise and the
    /// query would silently read nothing — else SDNN, else no HRV at all.
    var hrvKind: HKReadKind? {
        if capabilities.contains(.hrvRMSSD), HKReadKind.hrvRMSSDTypeAvailable { return .hrvRMSSD }
        if capabilities.contains(.hrvSDNN) { return .hrvSDNN }
        return nil
    }

    // MARK: - Sync

    /// T2 has no ingestion job to report on: the closest honest answer is when this provider last
    /// ran an anchored query against HealthKit. `nil` until the first fetch — never a fabricated
    /// "just now" (rule 5).
    public func syncStatus() async throws -> SyncStatus {
        try require(.sync)
        try requireHealthData()
        let last = lock.withLock { lastAnchorFetch }
        return SyncStatus(lastSync: last.map { $0.ISO8601Format() })
    }

    // MARK: - Internals

    private func require(_ capability: DataCapability) throws {
        guard capabilities.contains(capability) else { throw ProviderError.notCapable(capability) }
    }

    private func requireHealthData() throws {
        guard store.isHealthDataAvailable else { throw ProviderError.healthDataUnavailable }
    }

    /// One anchored page for `kind`, from the beginning of the store.
    ///
    /// The anchor is deliberately **not** replayed into the query: an anchored read resumes from
    /// where it stopped and returns only the delta, but a windowed recovery read needs the whole
    /// window on every call, so a resumed anchor would return an empty second page and the screen
    /// would go blank. The returned anchor is still kept (see `anchors`) for the incremental path
    /// and so `syncStatus()` has a real timestamp.
    private func samples(for kind: HKReadKind) async throws -> [HKSample] {
        guard let type = kind.sampleType else { return [] }
        let page = try await store.anchoredSamples(sampleType: type, anchor: nil, limit: HKObjectQueryNoLimit)
        lock.withLock {
            if let newAnchor = page.newAnchor { anchors[type.identifier] = newAnchor }
            lastAnchorFetch = now()
        }
        return page.samples
    }
}
#endif
