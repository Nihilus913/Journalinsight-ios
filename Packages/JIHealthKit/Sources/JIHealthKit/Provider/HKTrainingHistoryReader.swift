#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// W-OFFLINE2 OFF2-4: one heart-rate reading (tests build these instead of `HKQuantitySample`s).
public struct HeartRateReading: Sendable, Equatable {
    public var ts: Date
    public var bpm: Double
    public init(ts: Date, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

/// Seam: every heart-rate reading in `[start, end]`, any source (the debug seed included).
public protocol HealthStoreHeartRateQuerying: Sendable {
    func heartRates(start: Date, end: Date) async throws -> [HeartRateReading]
}

extension RealHealthStoreReader: HealthStoreHeartRateQuerying {
    public func heartRates(start: Date, end: Date) async throws -> [HeartRateReading] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKWorkoutUploadTypes.heartRate, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error {
                    if let code = (error as? HKError)?.code, code == .errorNoData || code == .errorAuthorizationNotDetermined
                        || code == .errorAuthorizationDenied {
                        continuation.resume(returning: []); return
                    }
                    continuation.resume(throwing: error); return
                }
                continuation.resume(returning: (samples ?? []).compactMap { $0 as? HKQuantitySample }
                    .map { HeartRateReading(ts: $0.startDate, bpm: $0.quantity.doubleValue(for: bpm)) })
            }
            store.execute(query)
        }
    }
}

/// W-OFFLINE2 OFF2-4 (B-50 slice 2): the Training tab's completed workouts with NO hub — HealthKit
/// workouts (every source) as `DayActivity` rows, newest first, plus an HR-only Activity detail.
/// History only: the plan, progression and weekday assignment stay "needs the hub" (slice 1).
/// Ids are negative (`-epoch seconds of the start`) so they can never collide with a hub
/// `core.activity` id, and stay stable across reads for the detail push.
public struct HKTrainingHistoryReader: TrainingHistoryProviding, ActivitySeriesProviding {
    public struct SeriesUnavailable: Error, Equatable, Sendable { public init() {} }

    private let store: any HealthStoreWorkoutQuerying
    private let heartRate: (any HealthStoreHeartRateQuerying)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    /// Look-back for an Activity detail id (the history screen never shows older rows).
    public static let seriesLookbackDays = 120

    public init(
        store: any HealthStoreWorkoutQuerying,
        heartRate: (any HealthStoreHeartRateQuerying)?,
        calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store; self.heartRate = heartRate; self.calendar = calendar; self.now = now
    }

    public static func activityId(start: Date) -> Int { -max(1, Int(start.timeIntervalSince1970.rounded(.down))) }

    public func recentWorkouts(days: Int) async throws -> [DayActivity] {
        try await records(days: days).map(Self.activity)
    }

    /// The `/training/day/{date}` shape for one local day (activities only).
    public func trainingDay(date: String) async throws -> TrainingDayDetail {
        guard let day = Self.dayFormatter(calendar).date(from: date),
              let end = calendar.date(byAdding: .day, value: 1, to: day) else {
            return TrainingDayDetail(date: date, activities: [], exerciseSets: [])
        }
        let rows = try await store.allWorkouts(start: day, end: end)
            .filter { $0.start >= day && $0.start < end }.sorted { $0.start > $1.start }
        return TrainingDayDetail(date: date, activities: rows.map(Self.activity), exerciseSets: [])
    }

    /// HR-only series (no route / speed on the phone's read): `splits == []`, pace nil.
    public func activitySeries(activityId: Int) async throws -> ActivitySeries {
        guard let heartRate,
              let r = try await records(days: Self.seriesLookbackDays).first(where: { Self.activityId(start: $0.start) == activityId })
        else { throw SeriesUnavailable() }
        let readings = try await heartRate.heartRates(start: r.start, end: r.end).sorted { $0.ts < $1.ts }
        guard let first = readings.first else { throw SeriesUnavailable() }
        let points = Self.bucketed(readings.map { (t: $0.ts.timeIntervalSince(first.ts), hr: $0.bpm) }, max: 300)
        return ActivitySeries(activityId: activityId, type: AppleWorkoutSport.name(r.activityType), splits: [],
                              points: points, hrOnly: true, caption: "Heart rate from Apple Health on this iPhone.")
    }

    @concurrent
    private func records(days: Int) async throws -> [HKWorkoutRecord] {
        let today = calendar.startOfDay(for: now())
        guard let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        return try await store.allWorkouts(start: start, end: end)
            .filter { $0.start >= start && $0.start < end }   // a workout belongs to the day it started on
            .sorted { $0.start > $1.start }
    }

    static func activity(_ r: HKWorkoutRecord) -> DayActivity {
        let iso = ISO8601DateFormatter()
        return DayActivity(activityId: activityId(start: r.start), type: AppleWorkoutSport.name(r.activityType),
                           name: nil, durationSec: r.end.timeIntervalSince(r.start),
                           distanceM: r.distanceM.flatMap { $0 > 0 ? $0 : nil }, source: "apple",
                           avgHr: r.avgHRBpm.map { Int($0.rounded(.down)) }, maxHr: r.maxHRBpm.map { Int($0.rounded()) },
                           startTimeUtc: iso.string(from: r.start))
    }

    static func bucketed(_ samples: [(t: Double, hr: Double)], max: Int) -> [ActivitySeriesPoint] {
        guard samples.count > max, let last = samples.last?.t, last > 0 else {
            return samples.map { ActivitySeriesPoint(t: $0.t, hr: $0.hr, paceSPerKm: nil) }
        }
        let width = last / Double(max)
        var buckets: [Int: (t: Double, sum: Double, n: Double)] = [:]
        for s in samples {
            let i = min(max - 1, Int(s.t / width))
            let b = buckets[i] ?? (t: Double(i) * width, sum: 0, n: 0)
            buckets[i] = (b.t, b.sum + s.hr, b.n + 1)
        }
        return buckets.keys.sorted().map { let b = buckets[$0]!; return ActivitySeriesPoint(t: b.t, hr: b.sum / b.n, paceSPerKm: nil) }
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
#endif
