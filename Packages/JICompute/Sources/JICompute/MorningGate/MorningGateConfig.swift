import Foundation

/// Threshold/coefficient block ported from `scripts/morning_go.py` L73-155
/// (via the RN oracle `mobile/src/compute/morningGate/config.ts`).
///
/// Every compute function takes a `config` defaulting to ``MorningGateConfig/default``,
/// so thresholds become editable in-app later without touching the logic.
///
/// Some constants are consumed only by `fetch_db`'s SQL or by `main()`'s notify
/// plumbing in the Python source — both DB/file I/O and notification sinks are
/// out of scope for this pure port. They are kept for completeness of the
/// constants block and commented as such. `baselineBf` is additionally dead in
/// `morning_go.py` itself — carried through unchanged.
///
/// Integer-vs-float types are load-bearing: `f"protein {PROTEIN_TARGET}g"`
/// renders `172g` for an `int` and `172.0g` for a `float`, so every constant
/// that reaches a verdict string keeps the Python type it has.
public nonisolated struct MorningGateConfig: Hashable, Sendable {
    /// Display-fallback daily kcal target; YAZIO's synced goal wins when present.
    public var kcalTarget: Int
    /// Display-fallback daily protein target (g).
    public var proteinTarget: Int
    /// Display-fallback daily carb target (g). Mirrors YAZIO.
    public var carbTarget: Int
    /// Display-fallback daily fat target (g). Unused by `evaluate()` (`fetch_db` only).
    public var fatTarget: Int
    /// Daily step target.
    public var stepTarget: Int
    /// Weight-loss rate above which the report suggests eating +200 kcal/day (kg/wk).
    public var lossFastKgWk: Double
    /// Weight-loss rate below which the report flags tracking gaps (kg/wk).
    public var lossSlowKgWk: Double
    /// ISO date the cut started — trend warnings suppressed for the first week.
    public var cutStart: String
    /// Minimum sleep duration (hours) below which the night reads amber.
    public var minSleepH: Double
    /// Respiration delta (breaths/min above the 14d baseline) that reads amber.
    public var respDeltaAmber: Double
    /// Reps at/above which all sets on the last session trigger a +10kg progression note.
    public var progressionReps: Int
    /// Target % of strict tracked days since cut start (KPI display only).
    public var trackRateTarget: Int
    /// Gate-compliance experiment toggle. The RN oracle gates the experiment
    /// line on this; `morning_go.py` gates only on `experiment_intervals`
    /// being present, and the flag has been `True` for every golden.
    public var gateExperimentActive: Bool
    /// ISO date the experiment started — `fetch_db` SQL filter only.
    public var gateExperimentStart: String
    /// Interval sessions to collect before the experiment's endpoint. Fallback
    /// only: `MorningGateDb.experimentTarget` (the active `plan.gate_challenge`
    /// row) wins when present.
    public var gateExperimentTarget: Int
    /// 3-day sliding carb average floor (g/day) below which the glycogen watch fires.
    public var carb3dWatch: Int
    /// Strict tracked-day kcal floor — `fetch_db` SQL only.
    public var strictKcal: Int
    /// Strict tracked-day minimum logged meals — `fetch_db` SQL only.
    public var strictMeals: Int
    /// Cut-phase target bodyweight (kg).
    public var targetWeight: Double
    /// Cut-phase target body-fat %.
    public var targetBf: Double
    /// Cut-phase starting bodyweight (kg) — the 0% end of the target progress bar.
    public var baselineWeight: Double
    /// Cut-phase starting body-fat % — unused inside `morning_go.py` itself.
    public var baselineBf: Double
    /// Activity types that satisfy a strength (or optional Day 4) session.
    public var strengthTypes: Set<String>
    /// Activity types that satisfy a Z2/cardio day, and `reducedCompliant`'s cardio check.
    public var cardioTypes: Set<String>
    /// Activity types that satisfy an interval day — excludes `multi_sport`
    /// (audit A3: "the 4x4 is NOT substitutable").
    public var intervalTypes: Set<String>
    /// Activity types counted toward `walkCreditMin` — `fetch_db` only.
    public var walkTypes: Set<String>
    /// Minutes a logged walk must run to satisfy a Z2 day on its own — `fetch_db` only.
    public var walkCreditMin: Int
    /// Weekday (Mon=0) of the weekly weigh-in/tape block. Friday, not Monday: a
    /// Monday weigh-in lands on weekend glycogen/water and reads high.
    public var weeklyBlockWeekday: Int
    /// Benchmark lifts tracked for progression/decline — `fetch_db` SQL only.
    public var benchmarkLifts: [String]

    public init(
        kcalTarget: Int,
        proteinTarget: Int,
        carbTarget: Int,
        fatTarget: Int,
        stepTarget: Int,
        lossFastKgWk: Double,
        lossSlowKgWk: Double,
        cutStart: String,
        minSleepH: Double,
        respDeltaAmber: Double,
        progressionReps: Int,
        trackRateTarget: Int,
        gateExperimentActive: Bool,
        gateExperimentStart: String,
        gateExperimentTarget: Int,
        carb3dWatch: Int,
        strictKcal: Int,
        strictMeals: Int,
        targetWeight: Double,
        targetBf: Double,
        baselineWeight: Double,
        baselineBf: Double,
        strengthTypes: Set<String>,
        cardioTypes: Set<String>,
        intervalTypes: Set<String>,
        walkTypes: Set<String>,
        walkCreditMin: Int,
        weeklyBlockWeekday: Int,
        benchmarkLifts: [String]
    ) {
        self.kcalTarget = kcalTarget
        self.proteinTarget = proteinTarget
        self.carbTarget = carbTarget
        self.fatTarget = fatTarget
        self.stepTarget = stepTarget
        self.lossFastKgWk = lossFastKgWk
        self.lossSlowKgWk = lossSlowKgWk
        self.cutStart = cutStart
        self.minSleepH = minSleepH
        self.respDeltaAmber = respDeltaAmber
        self.progressionReps = progressionReps
        self.trackRateTarget = trackRateTarget
        self.gateExperimentActive = gateExperimentActive
        self.gateExperimentStart = gateExperimentStart
        self.gateExperimentTarget = gateExperimentTarget
        self.carb3dWatch = carb3dWatch
        self.strictKcal = strictKcal
        self.strictMeals = strictMeals
        self.targetWeight = targetWeight
        self.targetBf = targetBf
        self.baselineWeight = baselineWeight
        self.baselineBf = baselineBf
        self.strengthTypes = strengthTypes
        self.cardioTypes = cardioTypes
        self.intervalTypes = intervalTypes
        self.walkTypes = walkTypes
        self.walkCreditMin = walkCreditMin
        self.weeklyBlockWeekday = weeklyBlockWeekday
        self.benchmarkLifts = benchmarkLifts
    }

    /// `DEFAULT_MORNING_GATE_CONFIG` — the live `morning_go.py` constants.
    public static let `default` = MorningGateConfig(
        kcalTarget: 1800,
        proteinTarget: 172,
        carbTarget: 160,
        fatTarget: 55,
        stepTarget: 15000,
        lossFastKgWk: 0.95,
        lossSlowKgWk: 0.30,
        cutStart: "2026-07-22",
        minSleepH: 6.0,
        respDeltaAmber: 2.0,
        progressionReps: 12,
        trackRateTarget: 90,
        gateExperimentActive: true,
        gateExperimentStart: "2026-08-13",
        gateExperimentTarget: 4,
        carb3dWatch: 120,
        strictKcal: 1200,
        strictMeals: 3,
        targetWeight: 68.5,
        targetBf: 14.0,
        baselineWeight: 80.2,
        baselineBf: 26.6,
        strengthTypes: ["strength_training", "multi_sport"],
        cardioTypes: ["running", "treadmill_running", "multi_sport"],
        intervalTypes: ["running", "treadmill_running"],
        walkTypes: ["walking", "hiking", "casual_walking", "speed_walking"],
        walkCreditMin: 40,
        weeklyBlockWeekday: 4,
        benchmarkLifts: ["BARBELL_BENCH_PRESS", "BARBELL_ROW"]
    )
}

/// `SESSION_BY_WEEKDAY` (`scripts/morning_go.py` L160-176). Monday = 0 …
/// Sunday = 6 (Python `date.weekday()` convention — see `CalendarMath.isoWeekday`).
public nonisolated let sessionByWeekday: [PlannedSession] = [
    PlannedSession(name: "Day 1 Full Upper + Z2 40min", type: .strength),
    PlannedSession(name: "Norwegian 4x4 intervals", type: .interval),
    PlannedSession(name: "Day 2 Full Upper + Z2 60min", type: .strength),
    PlannedSession(name: "Long Zone 2 75-90min", type: .z2),
    PlannedSession(name: "Day 3 Full Upper + Z2 60min", type: .strength),
    PlannedSession(name: "Norwegian 4x4 intervals", type: .interval),
    PlannedSession(name: "Rest", type: .rest),
]

/// Saturday flipped optional -> interval on this date (`morning_go.py`
/// `SATURDAY_INTERVAL_EFFECTIVE`). The lookup is date-aware so pre-changeover
/// dates keep evaluating under the schedule that was actually planned for them.
public nonisolated let saturdayIntervalEffective = "2026-08-30"

private let saturdayLegacy = PlannedSession(
    name: "Rest — optional Day 4 Full Upper parked until adjusted",
    type: .optional
)

/// `session_for(day)` — the planned session for an ISO date, respecting
/// schedule changeovers.
public nonisolated func sessionFor(_ iso: String) throws -> PlannedSession {
    let weekday = try CalendarMath.isoWeekday(iso)
    // Python compares `date` objects; ISO strings of equal width compare the
    // same way lexicographically, which is what the TS oracle relies on too.
    if weekday == 5 && iso < saturdayIntervalEffective { return saturdayLegacy }
    return sessionByWeekday[weekday]
}
