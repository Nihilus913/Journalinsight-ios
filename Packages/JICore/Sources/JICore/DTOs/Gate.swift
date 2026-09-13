public enum GateRecommendation: String, Codable, Sendable, Equatable {
    case progress = "PROGRESS", maintain = "MAINTAIN", reduce = "REDUCE", insufficientData = "INSUFFICIENT_DATA"
}

public struct GateAverages: Codable, Sendable, Equatable {
    public var avgKcal7d, avgProtein7d, avgWeightKg, avgRhrBpm, sleepScore7d, acwr: Double?
    public var avgBodyBattery, avgKcalBurned7d, avgKcalDeficit7d, estWeeklyWeightChangeKg: Double?
    public var trends: [String: String]
}

/// One row of the gate's daily table. Keys stay snake_case on purpose (kpiGate parity — rule metric
/// names are DATA matching plan.kpi_target); only `date` is promoted.
public struct DailyKpiRow: Codable, Sendable, Equatable {
    public var date: String
    public var values: [String: Double?]

    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var d = ""; var v: [String: Double?] = [:]
        for k in c.allKeys {
            if k.stringValue == "date" { d = try c.decode(String.self, forKey: k); continue }
            if let n = try? c.decodeIfPresent(Double.self, forKey: k) { v[k.stringValue] = n }
            else if let b = try? c.decodeIfPresent(Bool.self, forKey: k) { v[k.stringValue] = b ? 1 : 0 }
            else { v[k.stringValue] = nil }
        }
        date = d; values = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(date, forKey: Key(stringValue: "date"))
        for (k, val) in values { try c.encode(val, forKey: Key(stringValue: k)) }
    }
}

public struct GateResponse: Codable, Sendable, Equatable {
    public var averages: GateAverages
    public var daily: [DailyKpiRow]
    public var recommendation: GateRecommendation
    public var trackedDays, totalDays, minTrackedDays: Int
    public var triggeredRules, suggestions: [String]
}
