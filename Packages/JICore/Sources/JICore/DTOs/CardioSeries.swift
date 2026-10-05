import Foundation

/// B-94 b94p3 (Bevel BP-4) — `GET /api/v1/training/cardio-series?range=90d`: the Progress
/// screen's cardio series (HT `app/training/cardio_series.py`). `runs` = run-type activities
/// ≥ 1 km, oldest first, Garmin-vs-Apple duplicates counted once (Garmin wins);
/// `paceSecPerKm = durationSec / distanceM × 1000`. `avgHr == nil` = no HR (a gap, never 0).
/// `vo2max` = `core.vo2max_history` points in the same range.
public nonisolated struct CardioSeries: Codable, Sendable, Equatable {
    public var range: String
    public var from: String
    public var to: String
    public var runs: [CardioRun]
    public var vo2max: [Vo2maxPoint]

    public init(range: String, from: String, to: String, runs: [CardioRun], vo2max: [Vo2maxPoint]) {
        self.range = range; self.from = from; self.to = to; self.runs = runs; self.vo2max = vo2max
    }
}

public nonisolated struct CardioRun: Codable, Sendable, Equatable, Identifiable {
    public var activityId: Int64
    public var date: String
    public var type: String
    /// "garmin" | "apple"
    public var source: String
    public var distanceM: Double
    public var durationSec: Int
    public var paceSecPerKm: Double
    public var avgHr: Int?

    public var id: Int64 { activityId }

    public init(activityId: Int64, date: String, type: String, source: String, distanceM: Double,
                durationSec: Int, paceSecPerKm: Double, avgHr: Int?) {
        self.activityId = activityId; self.date = date; self.type = type; self.source = source
        self.distanceM = distanceM; self.durationSec = durationSec; self.paceSecPerKm = paceSecPerKm
        self.avgHr = avgHr
    }
}

public nonisolated struct Vo2maxPoint: Codable, Sendable, Equatable {
    public var date: String
    public var vo2max: Double
    /// "garmin" | "apple"
    public var source: String

    public init(date: String, vo2max: Double, source: String) {
        self.date = date; self.vo2max = vo2max; self.source = source
    }
}

public protocol CardioSeriesProviding: Sendable {
    /// `GET /api/v1/training/cardio-series?range=` — `range` = "<N>d" (1…400) or w | m | 6m | y.
    func cardioSeries(range: String) async throws -> CardioSeries
}
