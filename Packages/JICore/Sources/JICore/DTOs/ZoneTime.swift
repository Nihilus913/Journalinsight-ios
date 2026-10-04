import Foundation

/// B-95 (BP-26) — `GET /api/v1/training/zones?from&to&bucket&scope`: minutes per HR zone
/// (Z1..Z5) per day / week / month, re-binned on the hub from HR samples with the user's
/// current zone floors (`app/training/zones.py`). `minutes == nil` = no session with HR in that
/// bucket (never a zero, rule 5).
public nonisolated struct ZoneTimeRange: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var bucket: String
    public var scope: String
    /// The user's floors [Z1..Z5]; nil = zones not set (nothing binned).
    public var floors: [Int]?
    public var hrCapBpm: Int?
    public var buckets: [ZoneTimeBucket]
    public var totals: ZoneTimeTotals

    public init(from: String, to: String, bucket: String, scope: String, floors: [Int]?, hrCapBpm: Int?,
                buckets: [ZoneTimeBucket], totals: ZoneTimeTotals) {
        self.from = from; self.to = to; self.bucket = bucket; self.scope = scope; self.floors = floors
        self.hrCapBpm = hrCapBpm; self.buckets = buckets; self.totals = totals
    }
}

public nonisolated struct ZoneTimeBucket: Codable, Sendable, Equatable {
    public var start: String
    public var minutes: [Double]?
    public var sessions: Int
    public var sessionsNoHr: Int
    public init(start: String, minutes: [Double]?, sessions: Int, sessionsNoHr: Int) {
        self.start = start; self.minutes = minutes; self.sessions = sessions; self.sessionsNoHr = sessionsNoHr
    }
}

public nonisolated struct ZoneTimeTotals: Codable, Sendable, Equatable {
    public var minutes: [Double]?
    public var sessions: Int
    public var sessionsNoHr: Int
    public init(minutes: [Double]?, sessions: Int, sessionsNoHr: Int) {
        self.minutes = minutes; self.sessions = sessions; self.sessionsNoHr = sessionsNoHr
    }
}

public protocol ZoneTimeProviding: Sendable {
    /// `GET /api/v1/training/zones?from=YYYY-MM-DD&to=YYYY-MM-DD&bucket=day|week|month&scope=cardio|all`
    func trainingZones(from: String, to: String, bucket: String, scope: String) async throws -> ZoneTimeRange
}
