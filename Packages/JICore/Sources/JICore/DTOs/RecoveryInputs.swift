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
    /// W-B103 (B-103): sleeping breathing rate (Apple, Garmin fills) + Apple wrist temp; nil from an
    /// older hub. Scored only when the hub's `vitals` flag is on.
    public var respBpm: Double?
    public var wristTempC: Double?
    /// B-104 p2 (HT B-104 p1): where `hrvMs` came from — "apple" (Watch RMSSD) | "garmin" (Garmin
    /// nightly RMSSD, already × 0.95 hub-side = an estimate) | nil (no HRV that night, or an older
    /// hub that does not send it — then an `hrvMs` is the Watch's, as before).
    public var hrvSrc: String?

    public init(date: String, hrvMs: Double? = nil, rhrBpm: Double? = nil, sleepH: Double? = nil,
                deepH: Double? = nil, remH: Double? = nil, loadMin: Double? = nil,
                respBpm: Double? = nil, wristTempC: Double? = nil, hrvSrc: String? = nil) {
        self.date = date; self.hrvMs = hrvMs; self.rhrBpm = rhrBpm; self.sleepH = sleepH
        self.deepH = deepH; self.remH = remH; self.loadMin = loadMin
        self.respBpm = respBpm; self.wristTempC = wristTempC; self.hrvSrc = hrvSrc
    }

    /// B-104 p2: this night's HRV is a Garmin estimate (never true for an older hub's rows).
    public var isGarminHrv: Bool { hrvMs != nil && hrvSrc == "garmin" }
    /// B-104 p2: this night's HRV is the Watch's — `hrv_src` "apple", or missing (older hub).
    public var isWatchHrv: Bool { hrvMs != nil && hrvSrc != "garmin" }
}

/// W-FIX10 R-04 (HT DH-4) — the hub's own verdict on the recovery baseline, from the default window
/// the 05:10 gate uses: `calibrating` until `nights_needed` real Apple nights exist (after the
/// 2026-09-29 Garmin-copy purge). `components` is keyed `hrv` / `rhr` / `sleep` / `load`; `nights`
/// there is that component's own count of real values in the normal window.
public struct RecoveryCalibrationComponent: Codable, Sendable, Equatable {
    public var status: String
    public var nights: Int?
    public init(status: String, nights: Int?) { self.status = status; self.nights = nights }
    public var isCalibrating: Bool { status == "calibrating" }
}

public struct RecoveryCalibration: Codable, Sendable, Equatable {
    /// "ok" | "calibrating" | "missing".
    public var status: String
    public var calibrating: Bool
    public var nights: Int
    public var nightsNeeded: Int
    public var components: [String: RecoveryCalibrationComponent]

    public init(status: String, calibrating: Bool, nights: Int, nightsNeeded: Int,
                components: [String: RecoveryCalibrationComponent] = [:]) {
        self.status = status; self.calibrating = calibrating; self.nights = nights
        self.nightsNeeded = nightsNeeded; self.components = components
    }

    /// Tolerant: a missing `components` is empty, never a decode failure of the whole route.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        calibrating = try c.decodeIfPresent(Bool.self, forKey: .calibrating) ?? (status == "calibrating")
        nights = try c.decodeIfPresent(Int.self, forKey: .nights) ?? 0
        nightsNeeded = try c.decodeIfPresent(Int.self, forKey: .nightsNeeded) ?? 14
        components = try c.decodeIfPresent([String: RecoveryCalibrationComponent].self, forKey: .components) ?? [:]
    }

    public func component(_ key: String) -> RecoveryCalibrationComponent? { components[key] }

    /// True when the hub says this component's normal is still calibrating.
    public func isCalibrating(_ key: String) -> Bool { components[key]?.isCalibrating ?? false }
}

/// The route's envelope: `date` = the day the hub loaded for (hub-local today when not passed).
/// `calibration` = W-FIX10 R-04; nil from a hub before DH-4.
public struct RecoveryInputsReport: Codable, Sendable, Equatable {
    public var date: String
    public var days: [RecoveryInputDay]
    public var calibration: RecoveryCalibration?
    /// W-B103: the hub's `HT_RECOVERY_VITALS` flag — the phone scores breathing/wrist temp only when
    /// it is on. Missing (older hub or cache) = false.
    public var vitals: Bool
    public init(date: String, days: [RecoveryInputDay], calibration: RecoveryCalibration? = nil, vitals: Bool = false) {
        self.date = date; self.days = days; self.calibration = calibration; self.vitals = vitals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        days = try c.decode([RecoveryInputDay].self, forKey: .days)
        calibration = try c.decodeIfPresent(RecoveryCalibration.self, forKey: .calibration)
        vitals = try c.decodeIfPresent(Bool.self, forKey: .vitals) ?? false
    }
}
