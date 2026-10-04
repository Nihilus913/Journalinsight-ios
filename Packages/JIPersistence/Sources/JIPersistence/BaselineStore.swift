import Foundation
import GRDB

/// W-ONDEVICE O-6 (B-20) — where a nightly reading came from. `apple` = read from HealthKit on this
/// phone (never a Garmin Connect copy, see `HKSourceFilter`); `garmin` = only ever written by the
/// one-time hub seed (O-8). The two are never merged here: `JICompute`'s merge rule (Apple first,
/// Garmin fills, Garmin RMSSD x factor) runs on read.
public enum BaselineSource: String, Sendable, Hashable, CaseIterable {
    case apple, garmin
}

/// The nightly metrics the on-device verdict needs. Raw values in the hub's own units.
public enum BaselineMetric: String, Sendable, Hashable, CaseIterable {
    case hrvRmssdMs = "hrv_rmssd_ms"
    case rhrBpm = "rhr_bpm"
    case sleepDurationSec = "sleep_duration_sec"
    case sleepScore = "sleep_score"
}

/// One stored row: `(source, metric, date, value)`, `date` = the wake-up day `YYYY-MM-DD`.
public struct BaselineSample: Sendable, Equatable, Hashable {
    public var source: BaselineSource
    public var metric: BaselineMetric
    public var date: String
    public var value: Double

    public init(source: BaselineSource, metric: BaselineMetric, date: String, value: Double) {
        self.source = source; self.metric = metric; self.date = date; self.value = value
    }
}

/// All metrics one source has for one night — what the verdict compute reads.
public struct BaselineNight: Sendable, Equatable {
    public var source: BaselineSource
    public var date: String
    public var values: [BaselineMetric: Double]

    public init(source: BaselineSource, date: String, values: [BaselineMetric: Double]) {
        self.source = source; self.date = date; self.values = values
    }
}

/// W-ONDEVICE O-6 (B-20): the on-device baseline store over `baseline_sample`
/// (`v6_ondevice_baseline`).
///
/// Only raw nightly values are kept — **recompute-on-read**: median / MAD / ln-mean are derived
/// by `JICompute` from these rows every time, never persisted, so there is no cached aggregate to
/// invalidate when a late HealthKit sample corrects a night (scout §3.6; 120 d x 4 metrics is
/// tiny). Writes are replay-safe (`(source, metric, date)` primary key, last write wins), and every
/// write prunes rows older than `retentionDays` before `today` (the composite's 120-day window,
/// `readiness_composite.WINDOW`).
public struct BaselineStore: Sendable {
    /// Days kept, counting `today` itself.
    public static let retentionDays = 120

    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// Upserts `samples` (non-finite values are dropped, never stored as a fake zero — XC rule 5)
    /// and prunes everything older than the retention window ending on `today`.
    public func record(_ samples: [BaselineSample], today: String) throws {
        let cutoff = Self.addDays(-(Self.retentionDays - 1), to: today)
        try db.pool.write { db in
            for s in samples where s.value.isFinite {
                try db.execute(
                    sql: """
                    INSERT INTO baseline_sample (source, metric, date, value) VALUES (?, ?, ?, ?)
                    ON CONFLICT(source, metric, date) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [s.source.rawValue, s.metric.rawValue, s.date, s.value]
                )
            }
            if let cutoff {
                try db.execute(sql: "DELETE FROM baseline_sample WHERE date < ?", arguments: [cutoff])
            }
        }
    }

    /// One metric's rows dated on/before `through`, oldest first (`source` nil = both sources).
    public func series(metric: BaselineMetric, source: BaselineSource? = nil, through: String) throws -> [BaselineSample] {
        try db.pool.read { db in
            var sql = "SELECT source, metric, date, value FROM baseline_sample WHERE metric = ? AND date <= ?"
            var args: [any DatabaseValueConvertible] = [metric.rawValue, through]
            if let source { sql += " AND source = ?"; args.append(source.rawValue) }
            sql += " ORDER BY date ASC, source ASC"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).compactMap(Self.sample)
        }
    }

    /// Every night on/before `through`, one entry per `(source, date)`, oldest first (apple before
    /// garmin on the same date).
    public func nightly(through: String) throws -> [BaselineNight] {
        let rows = try db.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT source, metric, date, value FROM baseline_sample WHERE date <= ?
                ORDER BY date ASC, source ASC
                """, arguments: [through]).compactMap(Self.sample)
        }
        var out: [BaselineNight] = []
        for row in rows {
            if let last = out.last, last.date == row.date, last.source == row.source {
                out[out.count - 1].values[row.metric] = row.value
            } else {
                out.append(BaselineNight(source: row.source, date: row.date, values: [row.metric: row.value]))
            }
        }
        return out
    }

    /// Rows stored for `source` (Developer screen + the O-8 "already seeded" check).
    public func count(source: BaselineSource) throws -> Int {
        try db.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM baseline_sample WHERE source = ?", arguments: [source.rawValue]) ?? 0
        }
    }

    private static func sample(_ row: Row) -> BaselineSample? {
        guard let source = BaselineSource(rawValue: row["source"]), let metric = BaselineMetric(rawValue: row["metric"]) else { return nil }
        return BaselineSample(source: source, metric: metric, date: row["date"], value: row["value"])
    }

    /// `YYYY-MM-DD` + `days`, in a fixed UTC Gregorian calendar (a pure date-key shift; no wall
    /// clock involved, so DST can never skip or repeat a day key).
    static func addDays(_ days: Int, to key: String) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let shifted = cal.date(byAdding: .day, value: days, to: date) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
