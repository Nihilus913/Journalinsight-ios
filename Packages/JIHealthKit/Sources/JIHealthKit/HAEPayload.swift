import Foundation

/// Health-Auto-Export envelope the hub's `POST /api/v1/ingest/apple-health` expects (frozen
/// contract, W2d card): `{"data":{"metrics":[{"name","units","data":[{"date","qty","source"?}]}]}}`.
/// Pure Codable/value types — no `HealthKit` import here — so payload assembly and encoding can
/// be tested on any `swift test` host without a real health store.
public struct HAEEnvelope: Encodable, Sendable, Equatable {
    public var data: HAEEnvelopeData
    public init(metrics: [HAEMetric]) { self.data = HAEEnvelopeData(metrics: metrics) }
}

public struct HAEEnvelopeData: Encodable, Sendable, Equatable {
    public var metrics: [HAEMetric]
}

public struct HAEMetric: Encodable, Sendable, Equatable {
    public var name: String
    public var units: String
    public var data: [HAEDataPoint]
    public init(name: String, units: String, data: [HAEDataPoint]) {
        self.name = name; self.units = units; self.data = data
    }
}

/// One sample on the wire. `qty` covers every metric except `sleep_analysis`, which instead
/// carries `sleepEnd` + per-stage hour totals (`deep`/`core`/`rem`/`awake`/`asleep`) — the shape
/// is a union because Health Auto Export itself unions them per metric name, and the hub's
/// `hae_bridge.py` branches on `name` to know which fields to read. Property names here are the
/// exact wire keys (including the camelCase `sleepEnd`) — `HubClient.post` must encode this type
/// WITHOUT `.convertToSnakeCase` (see its doc comment) or `sleepEnd` would corrupt to `sleep_end`.
public struct HAEDataPoint: Encodable, Sendable, Equatable {
    public var date: String
    public var qty: Double?
    public var source: String?
    public var sleepEnd: String?
    public var deep: Double?
    public var core: Double?
    public var rem: Double?
    public var awake: Double?
    public var asleep: Double?

    public init(
        date: String, qty: Double? = nil, source: String? = nil,
        sleepEnd: String? = nil, deep: Double? = nil, core: Double? = nil,
        rem: Double? = nil, awake: Double? = nil, asleep: Double? = nil
    ) {
        self.date = date; self.qty = qty; self.source = source
        self.sleepEnd = sleepEnd; self.deep = deep; self.core = core
        self.rem = rem; self.awake = awake; self.asleep = asleep
    }
}

/// Hub response to a successful upload (frozen contract note); `422` bodies decode to `HubError`
/// via `HubClient.post`'s normal non-2xx path, never this type.
public struct HAEUploadResponse: Decodable, Sendable, Equatable {
    public var status: String
    public var days: Int?
    public var rowsLoaded: Int?
    public var dates: [String]?
}

/// Metric names the hub maps today (frozen contract note). `heartRateVariabilityRMSSD` is listed
/// separately per the note ("the uploader MAY also send `heart_rate_variability_rmssd`... the hub
/// column is B-5, not this wave") — included here so a caller CAN send it, but nothing in this
/// wave wires it up.
public enum HAEMetricName {
    public static let stepCount = "step_count"
    public static let activeEnergy = "active_energy"
    public static let exerciseTime = "apple_exercise_time"
    public static let restingHeartRate = "resting_heart_rate"
    /// Day-average SDNN, per the frozen contract note.
    public static let heartRateVariability = "heart_rate_variability"
    public static let heartRateVariabilityRMSSD = "heart_rate_variability_rmssd"
    public static let sleepAnalysis = "sleep_analysis"
    public static let weightBodyMass = "weight_body_mass"
    public static let bodyFatPercentage = "body_fat_percentage"
    public static let leanBodyMass = "lean_body_mass"
    public static let bodyMassIndex = "body_mass_index"
}

public enum HAEDate {
    /// `"YYYY-MM-DD HH:MM:SS +ZZZZ"` — the exact Health-Auto-Export date shape `hae_bridge.py`
    /// parses. Always formatted in the sample's own timezone (defaults to `.current`, the
    /// device's), per the contract note "dates carry the local offset" — never UTC.
    public static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.string(from: date)
    }
}
