#if canImport(HealthKit)
import Foundation
import HealthKit
import JIHub
import Synchronization

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
    /// Anchor generation (B-65). Bumping it gives the metric a fresh anchor key, i.e. one full
    /// `firstSyncDays` re-send — how a wire-shape change back-fills the hub's baseline window.
    public let anchorVersion: Int
    /// WD-6 (DEV-13): when set, the uploader sends HealthKit's source-merged DAILY totals in this
    /// unit (statistics query) instead of `mapSamples`' raw samples. Raw samples of a cumulative
    /// type overlap across devices and straddle midnight, so the hub's per-day sum doubled or
    /// split days (09-18 = 3403 kcal, 09-19 = 1085 against a steady ~1900). Set automatically for
    /// basal energy (`dailyTotalTypes`), so every caller's spec gets it.
    public let dailyTotalUnit: HKUnit?
    /// `hk.upload.anchor.<type>` (version 1) or `hk.upload.anchor.<type>.v<n>` (n ≥ 2) — the
    /// App-Group `UserDefaults` key this metric's `HKQueryAnchor` persists under, so a
    /// killed/resumed app resumes without re-uploading.
    public var anchorKey: String {
        anchorVersion <= 1 ? "hk.upload.anchor.\(sampleType.identifier)"
                           : "hk.upload.anchor.\(sampleType.identifier).v\(anchorVersion)"
    }

    public init(sampleType: HKSampleType, metricName: String, units: String, backgroundFrequency: HKUpdateFrequency, anchorVersion: Int = 1, mapSamples: @escaping @Sendable ([HKSample]) -> [HAEDataPoint]) {
        self.sampleType = sampleType
        self.metricName = metricName
        self.units = units
        self.backgroundFrequency = backgroundFrequency
        self.anchorVersion = anchorVersion
        self.mapSamples = mapSamples
        self.dailyTotalUnit = Self.dailyTotalTypes[sampleType.identifier]
    }

    /// Cumulative types uploaded as daily totals (WD-6) → their unit. Basal only: the hub's
    /// resting-kcal column is where the raw sum broke (W-DATA R7).
    public static var dailyTotalTypes: [String: HKUnit] {
        guard let basal = HKReadKind.basalEnergy.sampleType else { return [:] }
        return [basal.identifier: .kilocalorie()]
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
    /// to `unit` and dated at the day's local midnight. Was the native-RMSSD mapping until B-65
    /// (RMSSD now goes per reading, see `hrvRMSSDPerReading`); kept as a generic builder, no app
    /// caller today. Ordered by date so the envelope is deterministic. Non-quantity samples are
    /// skipped.
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
    /// wake day of their END time, 18:00 cutoff (a night ending the morning of day D belongs to D, matching
    /// how the contract's per-night `sleepEnd` is read), sums each stage's duration in hours, and
    /// emits `sleepEnd` = the night's latest sample end. `core` carries both `asleepCore` and the
    /// legacy `asleepUnspecified` value (pre-stage-tracking devices/writers, e.g. this app's own
    /// v1 backload marker) since neither distinguishes further stages. B-65: each point also
    /// carries `sleepSegments` — the night's asleep stages merged when overlapping or touching
    /// (gap ≤ 60 s); `awake`/`inBed` never form a segment; `nil` when the night has none.
    public static func sleepAnalysis(timeZone: @escaping @Sendable () -> TimeZone = { .current }) -> @Sendable ([HKSample]) -> [HAEDataPoint] {
        { samples in
            let categories = samples.compactMap { $0 as? HKCategorySample }
            var byNight: [Date: [HKCategorySample]] = [:]
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone()
            for sample in categories {
                // B-65: wake-day attribution with an 18:00 local cutoff — a sample ending at or
                // after 18:00 belongs to the NEXT day's night. Grouping by the plain end-day split
                // every night that crossed midnight into two points (the pre-midnight chunk landed
                // on D-1 and, via the hub's last-writer-wins sleep row, could overwrite D-1's
                // real night). Afternoon naps (ending before 18:00) stay on their own day.
                let night = cal.startOfDay(for: sample.endDate.addingTimeInterval(6 * 3600))
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
                let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                              HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                var merged: [(Date, Date)] = []
                for s in night.filter({ asleepValues.contains($0.value) }).sorted(by: { $0.startDate < $1.startDate }) {
                    if let last = merged.last, s.startDate.timeIntervalSince(last.1) <= 60 {
                        merged[merged.count - 1].1 = max(last.1, s.endDate)
                    } else {
                        merged.append((s.startDate, s.endDate))
                    }
                }
                let segments = merged.map { HAESleepSegment(start: HAEDate.format($0.0, timeZone: timeZone()), end: HAEDate.format($0.1, timeZone: timeZone())) }
                return HAEDataPoint(
                    date: HAEDate.format(latestEnd, timeZone: timeZone()),
                    source: night.first?.sourceRevision.source.name,
                    sleepEnd: HAEDate.format(latestEnd, timeZone: timeZone()),
                    deep: deep, core: core, rem: rem, awake: awake, asleep: asleepTotal,
                    sleepSegments: segments.isEmpty ? nil : segments
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
    /// unavailable on this OS. One point per reading in milliseconds, dated with the reading's
    /// own timestamp (B-65) — the hub classifies overnight vs daytime readings against the
    /// night's sleep segments. `anchorVersion: 2` = one 120-day re-send of the per-reading
    /// history for the 28-night baseline. Wire name = frozen `HAEMetricName.heartRateVariabilityRMSSD`.
    public static func hrvRMSSDPerReading(
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
            anchorVersion: 2,
            mapSamples: HKSampleMapping.perSample(unit: .secondUnit(with: .milli), timeZone: timeZone)
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
        guard let spec = HKMetricSpec.hrvRMSSDPerReading(sampleType: sampleType, backgroundFrequency: backgroundFrequency, timeZone: timeZone) else { return self }
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
    /// WD-6: the statistics query daily-total specs read (the real reader conforms); `nil` = those
    /// specs fall back to raw samples.
    private let statistics: (any HealthStoreUploadStatistics)?
    /// Local-day grid for daily totals (device zone).
    private let calendar: Calendar
    /// W-B81 A-4: the Apple-workout reader (the real reader conforms); `nil` = no workout upload.
    private let workoutReader: (any HealthStoreWorkoutUploadReading)?
    /// Offset the workout dates are written in (the device's, never UTC — frozen README).
    private let timeZone: TimeZone
    /// One workout sync at a time; a trigger that arrives mid-run asks for one more pass instead of
    /// a parallel one (observer + foreground + Connect firing together = no duplicate POSTs).
    private let workoutRun = Mutex(WorkoutRunState())

    public init(store: any HealthStoreReading, hub: HubClient, specs: [HKMetricSpec], appGroupSuite: String = HealthKitUploader.appGroupSuite,
                timeZone: TimeZone = .current) {
        self.store = store
        self.hub = hub
        self.specs = specs
        self.anchorDefaults = UserDefaults(suiteName: appGroupSuite)
        self.statistics = store as? any HealthStoreUploadStatistics
        self.calendar = Self.deviceCalendar()
        self.workoutReader = store as? any HealthStoreWorkoutUploadReading
        self.timeZone = timeZone
    }

    private static func deviceCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c
    }

    /// Test seam: inject a `UserDefaults` double directly, matching `HealthKitBackloader`'s own
    /// pattern for the same reason (a bogus suite name isn't guaranteed `nil` across toolchains).
    init(store: any HealthStoreReading, hub: HubClient, specs: [HKMetricSpec], defaults: UserDefaults?,
         statistics: (any HealthStoreUploadStatistics)? = nil, calendar: Calendar? = nil,
         workouts: (any HealthStoreWorkoutUploadReading)? = nil, timeZone: TimeZone = .current) {
        self.store = store
        self.hub = hub
        self.specs = specs
        self.anchorDefaults = defaults
        self.statistics = statistics
        self.calendar = calendar ?? Self.deviceCalendar()
        self.workoutReader = workouts
        self.timeZone = timeZone
    }

    /// The launch request — the only one the app makes without a tap. W-FIX8 M-1: it asks for the
    /// whole read set (`HKReadKind.allReadTypes`), not just the uploaded specs, so a read-only kind
    /// added later (dietary energy/macros B-73, fibre/sugar W-FIX7) is asked for on the next launch
    /// of a phone that granted Health before it existed. Already-answered types never re-prompt.
    public func requestAuthorization() async throws {
        guard store.isHealthDataAvailable else { throw HealthKitUploaderError.healthDataUnavailable }
        var types = Set(specs.map { $0.sampleType as HKObjectType }).union(HKReadKind.allReadTypes)
        // W-B81: the workout reader also needs the HR series, route, distance/energy and effort types.
        if workoutReader != nil { types.formUnion(HKWorkoutUploadTypes.readTypes) }
        try await store.requestAuthorization(toRead: types)
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
        // W-B81 A-4: a finished Watch workout wakes the app like the daily types do.
        if workoutReader != nil, let workoutType = HKReadKind.workouts.sampleType {
            try await store.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
            let query = store.startObserving(workoutType) { [weak self] completion in
                Task { [weak self] in
                    defer { completion() }
                    _ = try? await self?.syncWorkouts()
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
        if workoutReader != nil {
            do { results[Self.workoutsResultKey] = .success(try await syncWorkouts()) }
            catch { results[Self.workoutsResultKey] = .failure(error) }
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
    /// App-Group key holding the instant (ISO-8601, UTC) of the last 2xx upload POST (B-65).
    /// Settings shows it as "Last Apple upload HH:mm"; JIFeatures duplicates the literal.
    public nonisolated static let lastSuccessKey = "hk.upload.lastSuccess"

    /// Fetches anchored pages for one metric, maps each, POSTs it and advances the anchor per
    /// page. `@concurrent`: runs off the caller's actor — under `NonisolatedNonsendingByDefault`
    /// a plain `async` func inherits the MainActor of the Connect button, and mapping a large
    /// history there froze the app (2026-09-23). Returns the number of points uploaded.
    @discardableResult
    @concurrent
    func sync(_ spec: HKMetricSpec, now: Date = Date()) async throws -> Int {
        if let unit = spec.dailyTotalUnit, let statistics, let type = spec.sampleType as? HKQuantityType {
            return try await syncDailyTotals(spec, type: type, unit: unit, statistics: statistics, now: now)
        }
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
                let arrived = ISO8601DateFormatter().string(from: Date())
                anchorDefaults?.set(arrived, forKey: Self.lastSuccessKey)
                // WD-5 (DEV-12): per-type arrival, so the Apple Health screen never shows one
                // type's upload time for another (`HealthKitArrival.lastUpload`).
                anchorDefaults?.set(arrived, forKey: HealthKitArrival.key(for: spec.sampleType))
                uploaded += points.count
            }
            writeAnchor(page.newAnchor, key: spec.anchorKey)
            anchor = page.newAnchor
            guard page.samples.count >= Self.pageLimit else { return uploaded }
        }
    }

    // MARK: - Daily totals (WD-6)

    /// `hk.upload.dailyTotals.<type>`: day → the total the hub has already received.
    static func dailyLedgerKey(_ spec: HKMetricSpec) -> String { "hk.upload.dailyTotals.\(spec.sampleType.identifier)" }
    /// swift-fix5's start day (ISO): an install with a raw-sample anchor got TOMORROW here, so the
    /// switch day and yesterday's remainder were never sent (F6-10). Read once, for the migration.
    static func dailyStartKey(_ spec: HKMetricSpec) -> String { "\(dailyLedgerKey(spec)).since" }
    /// F6-10: first day (ISO) on the daily-total path. Days before it are the raw path's; from it
    /// on, the ledger says what the hub holds.
    static func dailyStartKeyV2(_ spec: HKMetricSpec) -> String { "\(dailyLedgerKey(spec)).start.v2" }
    private static let openStart = "0000-01-01"

    /// The anchored query only says WHICH local days changed; for each, the statistics query gives
    /// HealthKit's source-merged total. The hub sums a day's increment deliveries, so the POST
    /// carries total − already delivered (0.1 kcal steps); the hub's sum is the HealthKit total.
    /// Yesterday and today are always re-checked, so a finished day's final total goes out even
    /// when no new sample starts on it (F6-10). A day without a HealthKit total is skipped (never
    /// a 0). Ledger, start and anchor move only after a 2xx, so a failed POST is retried whole.
    ///
    /// Switch from the raw-sample path (an anchor exists, no start yet): the change page holds
    /// exactly the samples the hub has not seen, so for each day from the first changed day to
    /// today the hub holds (raw sum of the day) − (raw sum of the new samples), by sample start
    /// day like the raw path. That seeds the ledger, and the POST sends yesterday's remainder and
    /// today's total. An install that ran swift-fix5 (start stored as its switch day + 1, nothing
    /// sent since) restarts on its switch day with an empty ledger — nothing raw arrived that day.
    private func syncDailyTotals(_ spec: HKMetricSpec, type: HKQuantityType, unit: HKUnit,
                                 statistics: any HealthStoreUploadStatistics, now: Date) async throws -> Int {
        var anchor = readAnchor(spec.anchorKey)
        let hadAnchor = anchor != nil
        let windowStart = now.addingTimeInterval(-Double(Self.firstSyncDays) * 86_400)
        let since: Date? = anchor == nil ? windowStart : nil
        var touched = Set<Date>()
        var newSamples: [HKSample] = []
        while true {
            let page = try await store.anchoredSamples(sampleType: spec.sampleType, anchor: anchor, since: since, limit: Self.pageLimit)
            for sample in page.samples {
                var day = calendar.startOfDay(for: sample.startDate)
                let last = calendar.startOfDay(for: max(sample.startDate, sample.endDate.addingTimeInterval(-1)))
                while day <= last {
                    touched.insert(day)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            newSamples += page.samples
            anchor = page.newAnchor ?? anchor
            guard page.samples.count >= Self.pageLimit else { break }
        }
        let iso = { (d: Date) in HKSampleWindow.isoDay(d, calendar: self.calendar) }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let floorDay = iso(calendar.startOfDay(for: windowStart))
        let ledgerKey = Self.dailyLedgerKey(spec)
        var sent = (anchorDefaults?.dictionary(forKey: ledgerKey) as? [String: Double]) ?? [:]
        let round1 = { (v: Double) in (v * 10).rounded() / 10 }

        // Start day (v2), migrating on the first run of this build.
        let startKey = Self.dailyStartKeyV2(spec)
        var startDay: String
        var dayCandidates = touched.union([yesterday, today])
        var seeds: [String: Double] = [:]
        if let stored = anchorDefaults?.string(forKey: startKey) {
            startDay = stored
        } else if let legacy = anchorDefaults?.string(forKey: Self.dailyStartKey(spec)) {
            if legacy == Self.openStart {
                startDay = legacy
            } else {
                let legacyDate = calendar.date(from: DateComponents(
                    year: Int(legacy.prefix(4)), month: Int(legacy.dropFirst(5).prefix(2)), day: Int(legacy.dropFirst(8).prefix(2))))
                let switchDay = legacyDate.flatMap { calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: $0)) } ?? today
                startDay = iso(min(switchDay, today))
                dayCandidates.formUnion(daysFrom(min(switchDay, today), through: today))
            }
        } else if hadAnchor {
            let first = min(touched.min() ?? today, today)
            startDay = iso(first)
            dayCandidates.formUnion(daysFrom(first, through: today))
            let rawAll = try await rawSumsByStartDay(spec, unit: unit, from: first)
            let rawNew = rawSumsByStartDay(newSamples, unit: unit)
            for day in daysFrom(first, through: today) {
                let key = iso(day)
                seeds[key] = round1(max(0, (rawAll[key] ?? 0) - (rawNew[key] ?? 0)))
            }
        } else {
            startDay = Self.openStart
        }

        let days = dayCandidates.filter { $0 <= today && iso($0) >= startDay && iso($0) >= floorDay }.sorted()
        func persist() {
            sent = sent.filter { $0.key >= floorDay }
            anchorDefaults?.set(sent, forKey: ledgerKey)
            anchorDefaults?.set(startDay, forKey: startKey)
            writeAnchor(anchor, key: spec.anchorKey)
        }
        guard let first = days.first, let lastDay = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
            persist()
            return 0
        }
        let raw = try await statistics.dailySumsExcludingOwnWrites(for: type, unit: unit, start: first, end: end, calendar: calendar)
        let totals = Dictionary(raw.map { (iso($0.key), $0.value) }, uniquingKeysWith: +)
        var points: [HAEDataPoint] = []
        var delivered: [String: Double] = [:]
        for day in days {
            let key = iso(day)
            guard let total = totals[key].map(round1) else {
                // No HealthKit total yet: remember what the raw path left on the hub, send nothing.
                if sent[key] == nil, let seed = seeds[key], seed > 0 { delivered[key] = seed }
                continue
            }
            // A switch seed never exceeds the merged total: the raw days stay as they are.
            let already = sent[key] ?? seeds[key].map { min($0, total) } ?? 0
            let delta = round1(total - already)
            guard abs(delta) >= 0.05 else {
                if sent[key] == nil, seeds[key] != nil { delivered[key] = already }
                continue
            }
            points.append(HAEDataPoint(date: HAEDate.format(day, timeZone: calendar.timeZone), qty: delta, source: "HealthKit daily total"))
            delivered[key] = total
        }
        if !points.isEmpty {
            let envelope = HAEEnvelope(metrics: [HAEMetric(name: spec.metricName, units: spec.units, data: points)])
            let _: HAEUploadResponse = try await hub.post(Self.uploadPath, body: envelope)
            let arrived = ISO8601DateFormatter().string(from: Date())
            anchorDefaults?.set(arrived, forKey: Self.lastSuccessKey)
            anchorDefaults?.set(arrived, forKey: HealthKitArrival.key(for: spec.sampleType))
        }
        sent.merge(delivered) { _, new in new }
        persist()
        return points.count
    }

    /// Local days `[from, through]`, both start-of-day.
    private func daysFrom(_ from: Date, through: Date) -> [Date] {
        var out: [Date] = []
        var day = calendar.startOfDay(for: from)
        while day <= through {
            out.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// Raw per-day sums as the raw path delivered them: each sample whole, on its START day.
    private func rawSumsByStartDay(_ samples: [HKSample], unit: HKUnit) -> [String: Double] {
        var out: [String: Double] = [:]
        for case let q as HKQuantitySample in samples {
            out[HKSampleWindow.isoDay(q.startDate, calendar: calendar), default: 0] += q.quantity.doubleValue(for: unit)
        }
        return out
    }

    /// One-off raw read from `from` (fresh query, its anchor is discarded — the change feed's
    /// anchor stays the persisted one).
    private func rawSumsByStartDay(_ spec: HKMetricSpec, unit: HKUnit, from: Date) async throws -> [String: Double] {
        var cursor: HKQueryAnchor?
        var all: [HKSample] = []
        while true {
            let page = try await store.anchoredSamples(sampleType: spec.sampleType, anchor: cursor, since: calendar.startOfDay(for: from), limit: Self.pageLimit)
            all += page.samples
            cursor = page.newAnchor ?? cursor
            guard page.samples.count >= Self.pageLimit, cursor != nil else { break }
        }
        return rawSumsByStartDay(all, unit: unit)
    }

    // MARK: - Apple workouts (W-B81 A-4)

    /// `syncAll()` result key for the workout upload.
    public nonisolated static let workoutsResultKey = "workouts"
    /// Anchor of the `HKWorkout` change feed (same `hk.upload.anchor.<type>` scheme as the metrics).
    public nonisolated static let workoutAnchorKey = "hk.upload.anchor.HKWorkoutTypeIdentifier"
    /// HealthKit objects per anchored page — each workout pulls its HR series and route, so pages
    /// stay small (a 45-min outdoor run ≈ 2.7 k route points + 500 HR readings).
    public nonisolated static let workoutPageLimit = 25
    /// Workouts per POST, keeping one body well inside `HubClient`'s 15 s timeout.
    public nonisolated static let workoutBatchSize = 5

    /// Uploads Apple workouts new/changed since the persisted anchor (first run: the last
    /// `firstSyncDays` = 120 days, once). Idempotent on the hub by workout UUID. X-1: nothing is
    /// POSTed for an empty page, deletions are never sent, a failed read or POST sends nothing
    /// partial and leaves the anchor where it was (the page is retried whole). Returns the
    /// number of workouts sent.
    @discardableResult
    @concurrent
    public func syncWorkouts(now: Date = Date()) async throws -> Int {
        guard let reader = workoutReader else { return 0 }
        let mayRun = workoutRun.withLock { state -> Bool in
            if state.running { state.again = true; return false }
            state.running = true; return true
        }
        guard mayRun else { return 0 }
        var sent = 0
        do {
            repeat { sent += try await workoutPass(reader, now: now) }
            while workoutRun.withLock { state -> Bool in
                if state.again { state.again = false; return true }
                state.running = false; return false
            }
        } catch {
            workoutRun.withLock { $0 = WorkoutRunState() }
            throw error
        }
        return sent
    }

    private func workoutPass(_ reader: any HealthStoreWorkoutUploadReading, now: Date) async throws -> Int {
        var anchor = readAnchor(Self.workoutAnchorKey)
        let since: Date? = anchor == nil ? now.addingTimeInterval(-Double(Self.firstSyncDays) * 86_400) : nil
        var sent = 0
        while true {
            let page = try await reader.anchoredWorkoutRecords(anchor: anchor, since: since, limit: Self.workoutPageLimit)
            let workouts = page.records.map { AppleWorkoutMapper.payload($0, timeZone: timeZone) }
            var batchStart = 0
            while batchStart < workouts.count {
                let batch = Array(workouts[batchStart..<min(batchStart + Self.workoutBatchSize, workouts.count)])
                let _: HAEUploadResponse = try await hub.post(Self.uploadPath, body: HAEEnvelope(workouts: batch))
                let arrived = ISO8601DateFormatter().string(from: Date())
                anchorDefaults?.set(arrived, forKey: Self.lastSuccessKey)
                if let type = HKReadKind.workouts.sampleType { anchorDefaults?.set(arrived, forKey: HealthKitArrival.key(for: type)) }
                sent += batch.count
                batchStart += Self.workoutBatchSize
            }
            // Only after every batch of the page is on the hub.
            writeAnchor(page.newAnchor, key: Self.workoutAnchorKey)
            anchor = page.newAnchor ?? anchor
            guard page.fetchedCount >= Self.workoutPageLimit else { return sent }
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

/// `running`: a workout sync is in flight; `again`: a trigger arrived meanwhile → one more pass.
struct WorkoutRunState: Sendable {
    var running = false
    var again = false
}
#endif
