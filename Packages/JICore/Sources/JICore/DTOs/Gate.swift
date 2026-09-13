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
            // `JSON.decoder` sets `.keyDecodingStrategy = .convertFromSnakeCase` at the decoder level —
            // that strategy runs before this type ever sees a key, so `k.stringValue` for e.g.
            // "kcal_consumed" arrives already turned into "kcalConsumed". There is no per-container
            // opt-out, so restore the documented snake_case contract by reversing it here.
            let rawKey = Self.snakeCased(k.stringValue)
            if rawKey == "date" { d = try c.decode(String.self, forKey: k); continue }
            // `v[key] = nil` on a `[String: Double?]` REMOVES the entry (Dictionary subscript-assign-nil
            // semantics) — that would silently drop JSON `null` columns instead of keeping them
            // present-with-nil. Use `updateValue(nil, forKey:)` for every branch that should record a
            // key, and check `decodeNil` explicitly so a JSON `null` is distinguished from "not decodable
            // as Double/Bool" (both currently land as nil, but via the explicit-null path when it applies).
            if let isNull = try? c.decodeNil(forKey: k), isNull {
                v.updateValue(nil, forKey: rawKey)
            } else if let n = try? c.decode(Double.self, forKey: k) {
                v.updateValue(n, forKey: rawKey)
            } else if let b = try? c.decode(Bool.self, forKey: k) {
                v.updateValue(b ? 1 : 0, forKey: rawKey)
            } else {
                v.updateValue(nil, forKey: rawKey)
            }
        }
        date = d; values = v
    }

    /// Reverses Foundation's `.convertFromSnakeCase` (insert `_` before each uppercase letter, then
    /// lowercase it) so dynamic keys land back in their original wire form. Exact for this row's known
    /// column set (single-word segments, no adjacent capitals, e.g. "kcalConsumed" -> "kcal_consumed").
    private static func snakeCased(_ s: String) -> String {
        var result = ""
        for ch in s {
            if ch.isUppercase {
                result.append("_")
                result.append(contentsOf: ch.lowercased())
            } else {
                result.append(ch)
            }
        }
        return result
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(date, forKey: Key(stringValue: "date"))
        for (k, val) in values {
            let key = Key(stringValue: k)
            if let val {
                try c.encode(val, forKey: key)
            } else {
                try c.encodeNil(forKey: key)
            }
        }
    }
}

public struct GateResponse: Codable, Sendable, Equatable {
    public var averages: GateAverages
    public var daily: [DailyKpiRow]
    public var recommendation: GateRecommendation
    public var trackedDays, totalDays, minTrackedDays: Int
    public var triggeredRules, suggestions: [String]
}
