#if canImport(HealthKit)
import Foundation
import HealthKit
import JIHub

/// One Apple Watch metric this app reads and uploads. Deliberately HK-identifier-agnostic at the
/// call site inside this file (`HKQuantityTypeIdentifier`/`HKCategoryTypeIdentifier` construction
/// stays out of `JIHealthKit/Sources` per L1's identifier-isolation rule) — the caller (today,
/// `App/AppEnvironment.swift`; L1's `HKTypes` may supply this list once merged) hands in an
/// already-built `HKSampleType` plus the mapping closure that knows how to read it.
public struct HKMetricSpec: Sendable {
    public let sampleType: HKSampleType
    public let metricName: String
    public let units: String
    public let backgroundFrequency: HKUpdateFrequency
    /// Maps one page's samples to zero or more wire data points. Pure — no I/O. Takes the whole
    /// page (not one sample at a time) so a metric like `sleep_analysis`, whose wire shape is one
    /// point per NIGHT built from several category samples, can aggregate.
    public let mapSamples: @Sendable ([HKSample]) -> [HAEDataPoint]
    /// `hk.upload.anchor.<type>` — the App-Group `UserDefaults` key this metric's `HKQueryAnchor`
    /// persists under, so a killed/resumed app resumes without re-uploading.
    public var anchorKey: String { "hk.upload.anchor.\(sampleType.identifier)" }

    public init(sampleType: HKSampleType, metricName: String, units: String, backgroundFrequency: HKUpdateFrequency, mapSamples: @escaping @Sendable ([HKSample]) -> [HAEDataPoint]) {
        self.sampleType = sampleType
        self.metricName = metricName
        self.units = units
        self.backgroundFrequency = backgroundFrequency
        self.mapSamples = mapSamples
    }
}

/// Reusable `mapSamples` builders — generic over HK sample shape, never over a specific metric's
/// `HKQuantityTypeIdentifier` (the caller already picked that when it built the `HKSampleType`).
public enum HKSampleMapping {
    /// One HAE point per quantity sample, converted to `unit`, dated at the sample's `startDate`,
    /// `source` = the sample's originating HK source name (Watch preferred per the contract note
    /// — callers should prefer Watch-sourced samples upstream if more than one source is present;
    /// this mapper itself is source-agnostic and maps whatever the anchored query returns).
    public static func perSample(unit: HKUnit, timeZone: @escaping @Sendable () -> TimeZone = { .current }) -> @Sendable ([HKSample]) -> [HAEDataPoint] {
        { samples in
            samples.compactMap { sample in
                guard let q = sample as? HKQuantitySample else { return nil }
                return HAEDataPoint(
                    date: HAEDate.format(q.startDate, timeZone: timeZone()),
                    qty: q.quantity.doubleValue(for: unit),
                    source: q.sourceRevision.source.name
                )
            }
        }
    }

    /// One HAE point per LOCAL DAY: the arithmetic mean of that day's quantity samples, converted
    /// to `unit` and dated at the day's local midnight. Used by the native-RMSSD metric (B-5),
    /// whose hub column is a day average (`hae_bridge.py` averages `heart_rate_variability`
    /// points the same way) — sending one point per sample would push per-reading noise over the
    /// wire. Ordered by date so the envelope is deterministic. Non-quantity samples are skipped.
    public static func dayAverage(unit: HKUnit, timeZone: @escaping @Sendable () -> TimeZone = { .current }) -> @Sendable ([HKSample]) -> [HAEDataPoint] {
        { samples in
            let zone = timeZone()
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            var byDay: [Date: (sum: Double, count: Int, source: String?)] = [:]
            for case let q as HKQuantitySample in samples {
                let day = cal.startOfDay(for: q.startDate)
                let value = q.quantity.doubleValue(for: unit)
                let existing = byDay[day]
                byDay[day] = (
                    sum: (existing?.sum ?? 0) + value,
                    count: (existing?.count ?? 0) + 1,
                    source: existing?.source ?? q.sourceRevision.source.name
                )
            }
            return byDay
                .sorted { $0.key < $1.key }
                .map { day, acc in
                    HAEDataPoint(
                        date: HAEDate.format(day, timeZone: zone),
                        qty: acc.sum / Double(acc.count),
                        source: acc.source
                    )
                }
        }
    }

    /// `sleep_analysis`: one point per night. Groups `inBed`/asleep-stage category samples by the
    /// calendar day of their END time (a night ending the morning of day D belongs to D, matching
    /// how the contract's per-night `sleepEnd` is read), sums each stage's duration in hours, and
    /// emits `sleepEnd` = the night's latest sample end. `core` carries both `asleepCore` and the
    /// legacy `asleepUnspecified` value (pre-stage-tracking devices/writers, e.g. this app's own
    /// v1 backload marker) since neither distinguishes further stages.
    public static func sleepAnalysis(timeZone: @escaping @Sendable () -> TimeZone = { .current }) -> @Sendable ([HKSample]) -> [HAEDataPoint] {
        { samples in
            let categories = samples.compactMap { $0 as? HKCategorySample }
            var byNight: [Date: [HKCategorySample]] = [:]
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone()
            for sample in categories {
                let night = cal.startOfDay(for: sample.endDate)
                byNight[night, default: []].append(sample)
            }
            return byNight.map { _, night in
                var deep = 0.0, core = 0.0, rem = 0.0, awake = 0.0, asleepTotal = 0.0
                var latestEnd = night.first?.endDate ?? Date.distantPast
                for sample in night {
                    let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                    if sample.endDate > latestEnd { latestEnd = sample.endDate }
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += hours; asleepTotal += hours
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: core += hours; asleepTotal += hours
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem += hours; asleepTotal += hours
                    case HKCategoryValueSleepAnalysis.awake.rawValue: awake += hours
                    default: break // inBed and any future case: not a stage total, ignored here
                    }
                }
                return HAEDataPoint(
                    date: HAEDate.format(latestEnd, timeZone: timeZone()),
                    source: night.first?.sourceRevision.source.name,
                    sleepEnd: HAEDate.format(latestEnd, timeZone: timeZone()),
                    deep: deep, core: core, rem: rem, awake: awake, asleep: asleepTotal
                )
            }
        }
    }
}

/// B-5 native-RMSSD wiring. The RMSSD `HKSampleType` is NEVER resolved here — it comes from
/// `HKReadKind.hrvRMSSD` (`HKTypes.swift` is the only file in `Sources/JIHealthKit` allowed to
/// name HK identifiers, and it resolves RMSSD by raw string to dodge the iOS 27.0 simulator dyld
/// crash). On an OS without the type that lookup is `nil`, so the factory is `nil` too and the
/// uploader's spec list — and therefore the outgoing envelope — is simply unchanged.
extension HKMetricSpec {
    /// The `heart_rate_variability_rmssd` metric spec, or `nil` when the RMSSD type is
    /// unavailable on this OS. Day-average in milliseconds, matching the hub's column
    /// (`core.daily_vitals.hrv_rmssd_ms`, dso_key 4) — the wire name is the frozen
    /// `HAEMetricName.heartRateVariabilityRMSSD`.
    public static func hrvRMSSDDayAverage(
        sampleType: HKSampleType? = HKReadKind.hrvRMSSD.sampleType,
        backgroundFrequency: HKUpdateFrequency = .hourly,
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) -> HKMetricSpec? {
        guard let sampleType else { return nil }
        return HKMetricSpec(
            sampleType: sampleType,
            metricName: HAEMetricName.heartRateVariabilityRMSSD,
            units: "ms",
            backgroundFrequency: backgroundFrequency,
            mapSamples: HKSampleMapping.dayAverage(unit: .secondUnit(with: .milli), timeZone: timeZone)
        )
    }
}

extension Array where Element == HKMetricSpec {
    /// Appends the native-RMSSD spec when this OS exposes the type, and returns `self` untouched
    /// otherwise — the one call the app's spec list needs (`App/AppEnvironment.swift`, wired by a
    /// later row; this lane owns only `JIHealthKit`).
    public func appendingNativeRMSSD(
        sampleType: HKSampleType? = HKReadKind.hrvRMSSD.sampleType,
        backgroundFrequency: HKUpdateFrequency = .hourly,
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) -> [HKMetricSpec] {
        guard let spec = HKMetricSpec.hrvRMSSDDayAverage(sampleType: sampleType, backgroundFrequency: backgroundFrequency, timeZone: timeZone) else { return self }
        return self + [spec]
    }
}

public enum HealthKitUploaderError: Error, Equatable, Sendable {
    case healthDataUnavailable
}

/// Reads Apple Watch samples via `HealthStoreReading` and POSTs them to the hub's frozen
/// `POST /api/v1/ingest/apple-health` contract. Idempotent via `HKQueryAnchor` per sample type
/// (persisted in the App-Group suite, key `hk.upload.anchor.<type>`) — a re-run with nothing new
/// in HealthKit uploads 0 points. No mutable stored state, so this class is unconditionally
/// `Sendable` without `@unchecked`.
public final class HealthKitUploader: Sendable {
    public static let appGroupSuite = "group.toby913.JournalInsight"
    public static let uploadPath = "/api/v1/ingest/apple-health"

    private let store: any HealthStoreReading
    private let hub: HubClient
    private let specs: [HKMetricSpec]
    // UserDefaults is thread-safe by documented contract but predates Sendable annotation on
    // this SDK — same reasoning as `HealthKitBackloader.cursorDefaults`.
    private nonisolated(unsafe) let anchorDefaults: UserDefaults?

    public init(store: any HealthStoreReading, hub: HubClient, specs: [HKMetricSpec], appGroupSuite: String = HealthKitUploader.appGroupSuite) {
        self.store = store
        self.hub = hub
        self.specs = specs
        self.anchorDefaults = UserDefaults(suiteName: appGroupSuite)
    }

    /// Test seam: inject a `UserDefaults` double directly, matching `HealthKitBackloader`'s own
    /// pattern for the same reason (a bogus suite name isn't guaranteed `nil` across toolchains).
    init(store: any HealthStoreReading, hub: HubClient, specs: [HKMetricSpec], defaults: UserDefaults?) {
        self.store = store
        self.hub = hub
        self.specs = specs
        self.anchorDefaults = defaults
    }

    public func requestAuthorization() async throws {
        guard store.isHealthDataAvailable else { throw HealthKitUploaderError.healthDataUnavailable }
        try await store.requestAuthorization(toRead: Set(specs.map { $0.sampleType as HKObjectType }))
    }

    /// Enables background delivery for every configured metric and registers an observer that
    /// uploads on each HealthKit-delivered update. Returns the live `HKObserverQuery`s so the
    /// caller (e.g. `AppEnvironment`) can retain them for the process lifetime — `HKHealthStore`
    /// does not retain observer queries itself.
    @discardableResult
    public func startBackgroundDelivery() async throws -> [HKObserverQuery] {
        var queries: [HKObserverQuery] = []
        for spec in specs {
            try await store.enableBackgroundDelivery(for: spec.sampleType, frequency: spec.backgroundFrequency)
            let query = store.startObserving(spec.sampleType) { [weak self] completion in
                Task { [weak self] in
                    defer { completion() }
                    _ = try? await self?.sync(spec)
                }
            }
            queries.append(query)
        }
        return queries
    }

    /// Runs every configured metric once (e.g. a manual "sync now" or the initial post-connect
    /// sync); errors are per-metric so one failing upload doesn't block the rest.
    @discardableResult
    @concurrent
    public func syncAll() async -> [String: Result<Int, Error>] {
        var results: [String: Result<Int, Error>] = [:]
        for spec in specs {
            do { results[spec.metricName] = .success(try await sync(spec)) }
            catch { results[spec.metricName] = .failure(error) }
        }
        return results
    }

    /// Fetches the anchored page for one metric, maps it, and — only when there's at least one
    /// mapped point — POSTs it and advances the anchor. Returns the number of points uploaded.
    /// First-sync window: a type with no anchor yet uploads only this many days back — enough
    /// for the 120-day per-source baselines (B-20/B-65) without pulling years of samples.
    public nonisolated static let firstSyncDays = 120
    /// Page size for the anchored query; a full page means "there may be more" and loops.
    public nonisolated static let pageLimit = 2_000

    /// Fetches anchored pages for one metric, maps each, POSTs it and advances the anchor per
    /// page. `@concurrent`: runs off the caller's actor — under `NonisolatedNonsendingByDefault`
    /// a plain `async` func inherits the MainActor of the Connect button, and mapping a large
    /// history there froze the app (2026-09-23). Returns the number of points uploaded.
    @discardableResult
    @concurrent
    func sync(_ spec: HKMetricSpec, now: Date = Date()) async throws -> Int {
        var anchor = readAnchor(spec.anchorKey)
        let since: Date? = anchor == nil ? now.addingTimeInterval(-Double(Self.firstSyncDays) * 86_400) : nil
        var uploaded = 0
        while true {
            let page = try await store.anchoredSamples(sampleType: spec.sampleType, anchor: anchor, since: since, limit: Self.pageLimit)
            let points = page.samples.isEmpty ? [] : spec.mapSamples(page.samples)
            if !points.isEmpty {
                let envelope = HAEEnvelope(metrics: [HAEMetric(name: spec.metricName, units: spec.units, data: points)])
                let response: HAEUploadResponse = try await hub.post(Self.uploadPath, body: envelope)
                _ = response // status/rows_loaded not currently surfaced further; kept for future logging
                uploaded += points.count
            }
            writeAnchor(page.newAnchor, key: spec.anchorKey)
            anchor = page.newAnchor
            guard page.samples.count >= Self.pageLimit else { return uploaded }
        }
    }

    // MARK: - Anchor persistence

    private func readAnchor(_ key: String) -> HKQueryAnchor? {
        guard let data = anchorDefaults?.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func writeAnchor(_ anchor: HKQueryAnchor?, key: String) {
        guard let anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        anchorDefaults?.set(data, forKey: key)
    }
}
#endif
