import Foundation

/// Input/output shapes for the morning readiness gate.
///
/// Transliterated from the RN oracle `mobile/src/compute/morningGate/types.ts`
/// (frozen v1.18.2), which in turn mirrors `HealthTraining/scripts/morning_go.py`.
/// Ground truth for behaviour is the Python-generated golden fixture
/// `morning.golden.json` — never this file.
///
/// The Python/TS data bags are snake_case dicts (they round-trip the real
/// on-disk JSON). Here they are Swift structs with Swift-cased properties; the
/// doc comment on each property names its Python key so the mapping stays
/// greppable, and the test fixture's `CodingKeys` carry the wire names.

// MARK: - Session

/// One planned session type. A `RawRepresentable` wrapper rather than a closed
/// `enum` because `session_done()` is called with whatever string the planner
/// row carries — the golden fixture exercises an unknown `"unknown"` type, and
/// Python's `if stype in (...)` chain simply falls through to `False`.
public nonisolated struct SessionType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let strength = SessionType(rawValue: "strength")
    public static let interval = SessionType(rawValue: "interval")
    public static let z2 = SessionType(rawValue: "z2")
    public static let optional = SessionType(rawValue: "optional")
    public static let rest = SessionType(rawValue: "rest")
}

/// `SESSION_BY_WEEKDAY`'s `(name, type)` tuple as a named value.
public nonisolated struct PlannedSession: Hashable, Sendable {
    public let name: String
    public let type: SessionType

    public init(name: String, type: SessionType) {
        self.name = name
        self.type = type
    }
}

// MARK: - Overnight vitals

/// Overnight vitals — mirrors `fetch_overnight()`'s return dict
/// (`scripts/morning_go.py` ~L216-261). `fetch_overnight` itself (Garmin API
/// I/O) is NOT ported; callers supply this shape.
public nonisolated struct MorningVitals: Hashable, Sendable {
    /// `sleep` — Garmin's 0-100 sleep score (integer).
    public var sleep: Int?
    /// `sleep_duration_h` — hours, already rounded to one decimal upstream.
    public var sleepDurationH: Double?
    /// `hrv` — last night's overnight average, ms (integer).
    public var hrv: Int?
    /// `hrv_status` — Garmin's own status string, e.g. `"LOW"`, `"BALANCED"`.
    public var hrvStatus: String?
    /// `rhr` — resting heart rate, bpm (integer).
    public var rhr: Int?
    /// `rhr_date` — ISO date the RHR reading is FROM. Garmin publishes no
    /// same-day row, so this is normally yesterday even though the value still
    /// gates today (see `rhrCarriedOver`).
    public var rhrDate: String?
    /// `steps_yesterday`.
    public var stepsYesterday: Int?
    /// `zone_drift` — a pre-rendered caveat line that `evaluate()` emits verbatim
    /// as its first condition when present. Present in `morning_go.py`'s
    /// `evaluate()` but absent from the RN oracle's `MorningVitals`; carried here
    /// because the Python file is L1's named source. No golden case sets it.
    public var zoneDrift: String?

    public init(
        sleep: Int? = nil,
        sleepDurationH: Double? = nil,
        hrv: Int? = nil,
        hrvStatus: String? = nil,
        rhr: Int? = nil,
        rhrDate: String? = nil,
        stepsYesterday: Int? = nil,
        zoneDrift: String? = nil
    ) {
        self.sleep = sleep
        self.sleepDurationH = sleepDurationH
        self.hrv = hrv
        self.hrvStatus = hrvStatus
        self.rhr = rhr
        self.rhrDate = rhrDate
        self.stepsYesterday = stepsYesterday
        self.zoneDrift = zoneDrift
    }
}

// MARK: - Benchmark lifts

/// One benchmark-lift session row (`fetch_db` ~L354-378). `date` is unused by
/// `liftFlags` itself; carried for fixture/shape fidelity.
public nonisolated struct BenchmarkLiftSession: Hashable, Sendable {
    public var date: String
    public var volume: Double
    public var minReps: Int?
    public var topKg: Double

    public init(date: String, volume: Double, minReps: Int?, topKg: Double) {
        self.date = date
        self.volume = volume
        self.minReps = minReps
        self.topKg = topKg
    }
}

/// One benchmark lift's session history, newest session first.
///
/// Python iterates `lifts.items()` and TS `Object.keys(lifts)` — both in
/// insertion order, and that order decides the order of the flag strings
/// `liftFlags` returns. A Swift `Dictionary` is unordered, so the port carries
/// an explicit ordered list instead of a map.
public nonisolated struct LiftHistory: Hashable, Sendable {
    public var name: String
    public var sessions: [BenchmarkLiftSession]

    public init(name: String, sessions: [BenchmarkLiftSession]) {
        self.name = name
        self.sessions = sessions
    }
}

// MARK: - DB figures

/// DB-derived figures fed into `evaluate()` — mirrors `fetch_db()`'s return
/// dict. `fetch_db` itself (Postgres I/O) is NOT ported; callers supply this
/// shape. Fields `evaluate()` never reads are carried anyway, exactly as the RN
/// oracle carries them, so a persistence slice can round-trip the real dict.
public nonisolated struct MorningGateDb: Hashable, Sendable {
    /// `y_kcal` — yesterday's logged energy.
    public var yKcal: Double?
    /// `y_protein` — yesterday's logged protein (g).
    public var yProtein: Double?
    /// `y_carbs` — display only; not read by `evaluate()`.
    public var yCarbs: Double?
    /// `y_fat` — display only; not read by `evaluate()`.
    public var yFat: Double?
    /// `y_kcal_goal` — display only; not read by `evaluate()`.
    public var yKcalGoal: Double?
    /// `y_protein_goal` — display only; not read by `evaluate()`.
    public var yProteinGoal: Double?
    /// `y_carbs_goal` — display only; not read by `evaluate()`.
    public var yCarbsGoal: Double?
    /// `y_fat_goal` — display only; not read by `evaluate()`.
    public var yFatGoal: Double?
    /// `latest_weight` — kg.
    public var latestWeight: Double?
    /// `latest_bf` — body fat %.
    public var latestBf: Double?
    /// `weight_trend_wk` — kg/week (see `trendKgWk`).
    public var weightTrendWk: Double?
    /// `lifts` — benchmark-lift history, in the order `fetch_db` supplies it.
    public var lifts: [LiftHistory]
    /// `y_resp` — yesterday's respiration rate (breaths/min).
    public var yResp: Double?
    /// `resp_baseline` — 14-day respiration baseline.
    public var respBaseline: Double?
    /// `eff_recent` — aerobic efficiency, recent 4 weeks.
    public var effRecent: Double?
    /// `eff_prior` — aerobic efficiency, prior 4 weeks.
    public var effPrior: Double?
    /// `kpi_days` — day index within the cut.
    public var kpiDays: Int?
    /// `track_rate` — % strict tracked days.
    public var trackRate: Int?
    /// `track_streak`.
    public var trackStreak: Int?
    /// `track_best`.
    public var trackBest: Int?
    /// `step_rate` — % days at/over the step target.
    public var stepRate: Int?
    /// `step_streak`.
    public var stepStreak: Int?
    /// `step_best`.
    public var stepBest: Int?
    /// `ex_rate` — % planned sessions done.
    public var exRate: Int?
    /// `ex_streak`.
    public var exStreak: Int?
    /// `ex_best`.
    public var exBest: Int?
    /// `experiment_intervals` — interval sessions banked in the gate experiment.
    public var experimentIntervals: Int?
    /// `experiment_target` — the active `plan.gate_challenge` target;
    /// `gateExperimentTarget` is only the empty-table fallback.
    public var experimentTarget: Int?
    /// `carbs_3d_avg` — 3-day sliding carb average (g/day).
    public var carbs3dAvg: Double?
    /// `_db_ok` — false when the DB query itself failed. Defaults true.
    public var dbOk: Bool?
    /// `_stale` — true when the day's sync failed; every derived line then
    /// carries a STALE caveat.
    public var stale: Bool?

    public init(
        yKcal: Double? = nil,
        yProtein: Double? = nil,
        yCarbs: Double? = nil,
        yFat: Double? = nil,
        yKcalGoal: Double? = nil,
        yProteinGoal: Double? = nil,
        yCarbsGoal: Double? = nil,
        yFatGoal: Double? = nil,
        latestWeight: Double? = nil,
        latestBf: Double? = nil,
        weightTrendWk: Double? = nil,
        lifts: [LiftHistory] = [],
        yResp: Double? = nil,
        respBaseline: Double? = nil,
        effRecent: Double? = nil,
        effPrior: Double? = nil,
        kpiDays: Int? = nil,
        trackRate: Int? = nil,
        trackStreak: Int? = nil,
        trackBest: Int? = nil,
        stepRate: Int? = nil,
        stepStreak: Int? = nil,
        stepBest: Int? = nil,
        exRate: Int? = nil,
        exStreak: Int? = nil,
        exBest: Int? = nil,
        experimentIntervals: Int? = nil,
        experimentTarget: Int? = nil,
        carbs3dAvg: Double? = nil,
        dbOk: Bool? = nil,
        stale: Bool? = nil
    ) {
        self.yKcal = yKcal
        self.yProtein = yProtein
        self.yCarbs = yCarbs
        self.yFat = yFat
        self.yKcalGoal = yKcalGoal
        self.yProteinGoal = yProteinGoal
        self.yCarbsGoal = yCarbsGoal
        self.yFatGoal = yFatGoal
        self.latestWeight = latestWeight
        self.latestBf = latestBf
        self.weightTrendWk = weightTrendWk
        self.lifts = lifts
        self.yResp = yResp
        self.respBaseline = respBaseline
        self.effRecent = effRecent
        self.effPrior = effPrior
        self.kpiDays = kpiDays
        self.trackRate = trackRate
        self.trackStreak = trackStreak
        self.trackBest = trackBest
        self.stepRate = stepRate
        self.stepStreak = stepStreak
        self.stepBest = stepBest
        self.exRate = exRate
        self.exStreak = exStreak
        self.exBest = exBest
        self.experimentIntervals = experimentIntervals
        self.experimentTarget = experimentTarget
        self.carbs3dAvg = carbs3dAvg
        self.dbOk = dbOk
        self.stale = stale
    }
}

// MARK: - State

/// Yesterday's gate flags — `evaluate()`'s 4th argument, and what
/// `prevFromState` returns.
public nonisolated struct MorningGatePrevState: Hashable, Sendable {
    public var hrvLow: Bool?
    public var rhrHigh: Bool?
    public var rhrDate: String?
    public var sleepLow: Bool?

    public init(hrvLow: Bool? = nil, rhrHigh: Bool? = nil, rhrDate: String? = nil, sleepLow: Bool? = nil) {
        self.hrvLow = hrvLow
        self.rhrHigh = rhrHigh
        self.rhrDate = rhrDate
        self.sleepLow = sleepLow
    }
}

/// The full on-disk state shape (`output/morning_go_state.json`), read by
/// `prevFromState`.
public nonisolated struct MorningGateState: Hashable, Sendable {
    public var date: String?
    public var hrvLow: Bool?
    public var rhrHigh: Bool?
    public var rhrDate: String?
    public var sleepLow: Bool?
    public var prev: MorningGatePrevState?

    public init(
        date: String? = nil,
        hrvLow: Bool? = nil,
        rhrHigh: Bool? = nil,
        rhrDate: String? = nil,
        sleepLow: Bool? = nil,
        prev: MorningGatePrevState? = nil
    ) {
        self.date = date
        self.hrvLow = hrvLow
        self.rhrHigh = rhrHigh
        self.rhrDate = rhrDate
        self.sleepLow = sleepLow
        self.prev = prev
    }
}

/// `evaluate()`'s `new_state` return value (written back to state on disk by
/// the caller).
public nonisolated struct MorningGateNewState: Hashable, Sendable {
    public var date: String
    public var hrvLow: Bool
    public var rhrHigh: Bool
    public var rhrDate: String?
    public var sleepLow: Bool

    public init(date: String, hrvLow: Bool, rhrHigh: Bool, rhrDate: String?, sleepLow: Bool) {
        self.date = date
        self.hrvLow = hrvLow
        self.rhrHigh = rhrHigh
        self.rhrDate = rhrDate
        self.sleepLow = sleepLow
    }
}

/// `evaluate()`'s `(verdict, conditions, new_state)` tuple as a named value.
public nonisolated struct EvaluateResult: Hashable, Sendable {
    public var verdict: String
    public var conditions: [String]
    public var newState: MorningGateNewState

    public init(verdict: String, conditions: [String], newState: MorningGateNewState) {
        self.verdict = verdict
        self.conditions = conditions
        self.newState = newState
    }
}

// MARK: - Trend rows

/// A `(date, weight_kg)` row as read from `core.body_metrics_daily`, oldest
/// first.
///
/// The weight column is `numeric`, so psycopg hands Python a `Decimal` and the
/// JSON fixture carries a decimal STRING for those rows. Python coerces with
/// `float(r[1])`, the TS oracle with `Number(r[1])`; both are correctly rounded,
/// as is `Double(_:)` here, so all three agree bit for bit.
public nonisolated struct TrendRow: Hashable, Sendable {
    public var date: String
    public var weight: Double

    public init(date: String, weight: Double) {
        self.date = date
        self.weight = weight
    }

    /// Row whose weight arrived as a decimal string (`numeric` column).
    /// A string that is not a number yields `nan`, mirroring `Number("x")`.
    public init(date: String, weightText: String) {
        self.init(date: date, weight: Double(weightText) ?? .nan)
    }
}
