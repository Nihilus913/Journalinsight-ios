/// B-57 W3 — `GET /api/v1/vitals/recovery-inputs`: the recovery-score inputs, from the same hub
/// loader the 05:10 gate reads (HT `app/vitals/recovery_inputs.py::load_recovery_inputs`), so the
/// phone's card and the gate's amber see the same numbers. HRV/RHR/sleep = Apple (dso 4) only;
/// load = moderate + 2·vigorous intensity minutes. Every value may be null — never a zero.
/// Keys arrive snake_case (`hrv_ms` …) and map through `JSON.decoder`'s `.convertFromSnakeCase`.
public struct RecoveryInputDay: Codable, Sendable, Equatable {
    public var date: String
    public var hrvMs: Double?
    public var rhrBpm: Double?
    public var sleepH: Double?
    public var deepH: Double?
    public var remH: Double?
    public var loadMin: Double?

    public init(date: String, hrvMs: Double? = nil, rhrBpm: Double? = nil, sleepH: Double? = nil,
                deepH: Double? = nil, remH: Double? = nil, loadMin: Double? = nil) {
        self.date = date; self.hrvMs = hrvMs; self.rhrBpm = rhrBpm; self.sleepH = sleepH
        self.deepH = deepH; self.remH = remH; self.loadMin = loadMin
    }
}

/// The route's envelope: `date` = the day the hub loaded for (hub-local today when not passed).
public struct RecoveryInputsReport: Codable, Sendable, Equatable {
    public var date: String
    public var days: [RecoveryInputDay]
    public init(date: String, days: [RecoveryInputDay]) { self.date = date; self.days = days }
}
