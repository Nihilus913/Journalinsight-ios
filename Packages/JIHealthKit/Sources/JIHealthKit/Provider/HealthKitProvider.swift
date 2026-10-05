#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore
import JICompute

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
    /// W-ONDEVICE O-7: the on-device verdict has no night for this day yet (payload = the day).
    /// Never a guessed verdict (rule 5); the hub answers the same case with "No verdict yet".
    case missing(String)
}

/// **T2**: the Apple-only provider — the app computes from HealthKit on this device instead of
/// asking the Mac hub (T1, `JIHub.HubDataProvider`). Spec §4.2's capability seam is what makes the
/// two interchangeable: every tile reads `capabilities`, never the provider type.
///
/// ## The gate is OFF unless the on-device verdict is wired (W-ONDEVICE O-7)
/// Without an `OnDeviceVerdictComputing` engine + `NightlyBaselineStoring` store, `gate`,
/// `morning` and `morningVerdict` throw `ProviderError.notCapable(.gate)` and
/// `appleWatchCapabilities` does not list them (W-FIX10 F10-4). The verdict is a comparison
/// against a **per-source baseline** (memory `project_source_agnostic_gate`), so it is computed
/// only from the on-device store (Apple nights, plus Garmin nights only from the O-8 hub seed).
/// With both wired (DEBUG/Developer toggle only — Release stays `.hub` until the 14-day dual run,
/// O-10), `.morning` + `.morningVerdict` flip ON; `.gate` (`GateResponse`, KPI averages incl.
/// nutrition) stays the hub's.
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
    /// W-ONDEVICE O-6: resolves a sample's source bundle id for `HKSourceFilter` (injectable: a
    /// package test cannot set a sample's source).
    private let sourceBundle: @Sendable (HKSample) -> String?
    /// W-ONDEVICE O-6: the on-device baseline store, nil = no on-device verdict wired.
    private let baseline: (any NightlyBaselineStoring)?
    /// W-ONDEVICE O-7: the on-device verdict compute; nil = the gate trio stays OFF.
    private let onDevice: (any OnDeviceVerdictComputing)?

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
        now: @escaping @Sendable () -> Date = Date.init,
        sourceBundle: @escaping @Sendable (HKSample) -> String? = HKSourceFilter.sampleBundle,
        baseline: (any NightlyBaselineStoring)? = nil,
        onDevice: (any OnDeviceVerdictComputing)? = nil
    ) {
        self.store = store
        // W-ONDEVICE O-7: `.morning` / `.morningVerdict` flip ON only when the on-device verdict
        // is enabled (an engine AND a store are wired — the DEBUG/Developer toggle; Release stays
        // `.hub`). `.gate` (`GateResponse`, the KPI averages) stays the hub's: it needs nutrition.
        var caps = capabilities
        if onDevice != nil, baseline != nil { caps.formUnion([.morning, .morningVerdict]) }
        self.capabilities = caps
        self.onDevice = onDevice
        self.calendar = calendar
        self.now = now
        self.sourceBundle = sourceBundle
        self.baseline = baseline
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

    /// W-ONDEVICE O-7: today's verdict computed on device, in the hub's `MorningResponse` shape.
    /// No night yet -> `verdict` nil ("No verdict yet"), never a guess. Nutrition fields
    /// (`carbs3dAvg`) stay nil: HealthKit cannot supply them.
    public func morning() async throws -> MorningResponse {
        try requireOnDevice(.morning)
        let day = todayKey
        let result = try await onDeviceVerdict(day: day)
        return .onDevice(
            verdict: result?.verdict, verdictDate: result == nil ? nil : day,
            carbWatchFloor: Self.carbWatchFloor, isStale: result == nil ? nil : false,
            gateSignals: result.map(OnDeviceVerdictLabel.signals)
        )
    }

    /// W-ONDEVICE O-7: the verdict for `date` computed on device (`MorningVerdict`, hub shape).
    /// Calibrating -> the verdict is still returned, `reason` labelled "Estimate — calibrating
    /// (N/28 nights)" (Toby Q2). No night -> `ProviderError.missing(date)`.
    public func morningVerdict(date: String) async throws -> MorningVerdict {
        try requireOnDevice(.morningVerdict)
        guard let result = try await onDeviceVerdict(day: date) else { throw ProviderError.missing(date) }
        return .onDevice(date: date, verdict: result.verdict, reason: OnDeviceVerdictLabel.reason(result),
                              sessionPrescription: result.sessionPrescription, computedAt: now().ISO8601Format())
    }

    /// The hub's `_CARB_3D_WATCH` (`app/planning/router.py`), served as `carb_watch_floor`.
    static let carbWatchFloor: Double = 120

    /// HealthKit nights read this far back on every verdict call (the night itself plus slack for
    /// a late-synced previous night); the 120-day backfill is `refreshBaseline()`'s job (pre-warm).
    static let verdictRefreshDays = 3
    /// RG-04: a cold store's one-time read (the store's retention window).
    static let coldRefreshDays = 120

    /// W-ONDEVICE O-7/O-9: refresh the store from HealthKit (Apple only), then compute `day` from
    /// the store. `nil` = no night for `day`. Errors (e.g. HealthKit's protected-data error on a
    /// locked phone) propagate so the trigger can fall back and retry on unlock.
    public func onDeviceVerdict(day: String) async throws -> OnDeviceVerdictResult? {
        guard let onDevice, let baseline else { throw ProviderError.notCapable(.gate) }
        try requireHealthData()
        // RG-04 / B-120: a cold store (no Apple night older than the short refresh — the 04:45
        // pre-warm never ran) reads the full window once, else the band saw 2/28 nights.
        let stored = try baseline.nightly(through: day)
        let cutoff = (try? CalendarMath.addDays(day, -Self.verdictRefreshDays)) ?? day
        let warm = stored.contains { $0.source == .apple && $0.date < cutoff }
        try await refreshBaseline(windowDays: warm ? Self.verdictRefreshDays : Self.coldRefreshDays)
        let input = OnDeviceVerdictInput(day: day, nights: try baseline.nightly(through: day))
        guard var result = try onDevice.compute(input) else { return nil }
        result.inputsDigest = input.digest
        result.wakeAt = try? await wakeTime(day: day)
        return result
    }

    /// O-10: the end of `day`'s main sleep (the hub's `main_nights` rule), nil without one.
    func wakeTime(day: String) async throws -> Date? {
        let window = HKSampleWindow(windowDays: Self.verdictRefreshDays, now: now(), calendar: calendar)
        let sleep = try await samples(for: .sleepAnalysis, since: window.start.addingTimeInterval(-86_400))
        return HKRecoveryAssembler.mainNights(sleep, window: window)[day]?.end
    }

    private func requireOnDevice(_ capability: DataCapability) throws {
        guard capabilities.contains(capability), onDevice != nil, baseline != nil else { throw ProviderError.notCapable(.gate) }
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
        // One day of slack before the window: a night's sleep starts the evening before its day.
        let since = window.start.addingTimeInterval(-86_400)
        let rhr = try await samples(for: .restingHeartRate, since: since)
        let hrv: [HKSample] = if let kind = hrvKind { try await samples(for: kind, since: since) } else { [] }
        let sleep = capabilities.contains(.sleepSummary) ? try await samples(for: .sleepAnalysis, since: since) : []
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

    // MARK: - Baseline store (W-ONDEVICE O-6)

    /// Reads the last `windowDays` of HealthKit nights (Garmin Connect copies already filtered out
    /// by `samples(for:since:)`) and upserts them into the baseline store as `apple` nights.
    /// Returns how many nights were written; 0 with no store wired. Replay-safe: the store keys by
    /// `(source, date)`, so a re-delivered night overwrites itself.
    @discardableResult
    public func refreshBaseline(windowDays: Int = 120) async throws -> Int {
        guard let baseline else { return 0 }
        let days = try await recovery(windowDays: windowDays)
        let nights = OnDeviceNight.apple(from: days)
        try baseline.record(nights, today: todayKey)
        return nights.count
    }

    /// Today's local `YYYY-MM-DD` in this provider's calendar.
    public var todayKey: String { HKSampleWindow(windowDays: 1, now: now(), calendar: calendar).days[0] }

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
    /// `since` bounds the read to the window (2026-09-23: an unbounded read of years of samples on
    /// the caller's MainActor froze the app once "read from watch" was switched on).
    /// W-FIX10 DH-3: the store's anchored read never returns this app's own writes (the Garmin
    /// backload) — `HKOwnWrites.anchoredPredicate` — so a backloaded Garmin night is never read
    /// back here as an Apple one.
    @concurrent
    private func samples(for kind: HKReadKind, since: Date) async throws -> [HKSample] {
        guard let type = kind.sampleType else { return [] }
        let page = try await store.anchoredSamples(sampleType: type, anchor: nil, since: since, limit: HKObjectQueryNoLimit)
        lock.withLock {
            if let newAnchor = page.newAnchor { anchors[type.identifier] = newAnchor }
            lastAnchorFetch = now()
        }
        // W-ONDEVICE O-6: never a Garmin Connect copy (see `HKSourceFilter`).
        return HKSourceFilter.keep(page.samples, bundleOf: sourceBundle)
    }
}
#endif
