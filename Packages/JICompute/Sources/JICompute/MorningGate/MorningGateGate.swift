import Foundation

/// Morning readiness gate — parity port of `scripts/morning_go.py`'s pure
/// compute core (1,528 L; `evaluate()` at ~L850).
///
/// Ground truth is the OUTPUT OF EXECUTING the Python functions, captured by
/// `scripts/parity/gen_golden_morning.py` into `morning.golden.json` and
/// replayed by `MorningGateTests.swift`. The RN oracle
/// `mobile/src/compute/morningGate/gate.ts` (frozen v1.18.2) is the
/// transliteration source; where it and `morning_go.py` differ, the comment at
/// that site says so and the Python wins.
///
/// Pure port ONLY — `fetch_db`, `fetch_overnight`, `fetch_latest_bf`,
/// `run_sync`, `acquire/release_lock`, `append_verdict`/`load_reduced_days`
/// (JSONL I/O), `load_state`/`load_dose_log` (file I/O), `notify_mac`/
/// `notify_iphone` (notification sinks) and `main()` are NOT ported; callers of
/// `evaluate()` supply their results as typed arguments instead.
///
/// | Python                     | Swift                     |
/// | -------------------------- | ------------------------- |
/// | `session_done`             | `sessionDone`             |
/// | `reduced_compliant`        | `reducedCompliant`        |
/// | `lift_flags`               | `liftFlags`               |
/// | `_trend_kg_wk`             | `trendKgWk`               |
/// | `consecutive_dose_index`   | `consecutiveDoseIndex`    |
/// | `rhr_carried_over`         | `rhrCarriedOver`          |
/// | `vitals_present`           | `vitalsPresent`           |
/// | `vitals_line`              | `vitalsLine`              |
/// | `_fmt`                     | `fmtValue`                |
/// | `_fmt_vs`                  | `fmtVs`                   |
/// | `_streak`                  | `streak`                  |
/// | `_best_streak`             | `bestStreak`              |
/// | `prev_from_state`          | `prevFromState`           |
/// | `_append_admin`            | `appendAdmin` (private)   |
/// | `evaluate`                 | `evaluate`                |
///
/// PARITY DEVIATION (documented, unavoidable): Python's `evaluate()` reads
/// `scripts/dose_log.json` via `load_dose_log()` internally (twice) to build the
/// dosed-dates set. That is file I/O, out of scope for a pure port, so this
/// `evaluate()` takes the dosed dates as an explicit `dosedDates` parameter
/// instead of reading a file. Every other input/output is unchanged.

// MARK: - session_done

/// Did the day's planned session actually happen?
///
/// On a Z2 day hitting the step target counts — walking IS the sanctioned
/// amber-day substitute, so following the protocol must never break the streak.
/// Interval days are NOT substitutable: the 4x4 is the quality session. An
/// optional Saturday counts only if it was really lifted.
public nonisolated func sessionDone(
    _ stype: SessionType,
    doneTypes: Set<String>,
    stepOk: Bool,
    longWalk: Bool,
    config: MorningGateConfig = .default
) -> Bool {
    if stype == .strength || stype == .optional { return !doneTypes.isDisjoint(with: config.strengthTypes) }
    if stype == .interval { return !doneTypes.isDisjoint(with: config.intervalTypes) }
    if stype == .z2 { return !doneTypes.isDisjoint(with: config.cardioTypes) || stepOk || longWalk }
    return false
}

// MARK: - reduced_compliant

/// On a REDUCED morning the prescription is easy Z2 or a walk — doing what the
/// report asked must count as the day's session (audit D1: "walk only" then
/// failing the walker).
public nonisolated func reducedCompliant(
    dayTypes: Set<String>,
    longWalk: Bool,
    config: MorningGateConfig = .default
) -> Bool {
    longWalk || !dayTypes.isDisjoint(with: config.cardioTypes)
}

// MARK: - _trend_kg_wk

/// Least-squares weight slope (kg/week) over `(date, weight)` rows, oldest
/// first.
///
/// Returns `nil` unless the window holds >= 4 points with >= 3 DISTINCT weights
/// (a frozen fortnight of carried-forward weigh-ins measures scale noise, not
/// fat — audit C1). Arithmetic is ordered to match Python's `sum()`/`zip()`
/// exactly (left-to-right float accumulation) for bit-exact parity.
public nonisolated func trendKgWk(_ rows: [TrendRow]) throws -> Double? {
    if rows.count < 4 { return nil }
    let vals = rows.map(\.weight)
    if Set(vals).count < 3 { return nil }
    let xs = try rows.map { try CalendarMath.diffDays($0.date, rows[0].date) }
    let mx = Double(xs.reduce(0, +)) / Double(xs.count)
    let my = vals.reduce(0.0, +) / Double(vals.count)
    let den = xs.reduce(0.0) { $0 + (Double($1) - mx) * (Double($1) - mx) }
    // Python's `if not den` is a truthiness test, so only an exact zero bails;
    // the TS oracle's `if (!den)` additionally bails on NaN. Python wins.
    if den == 0 { return nil }
    var num = 0.0
    for i in xs.indices { num += (Double(xs[i]) - mx) * (vals[i] - my) }
    let slope = num / den
    return pythonRound(slope * 7, 2)
}

// MARK: - consecutive_dose_index

/// 1-based position of `day` (ISO) within an unbroken run of dosed dates (0 if
/// undosed). Ambient HR offset roughly doubles by day 3.
public nonisolated func consecutiveDoseIndex(_ day: String, dosed: Set<String>) throws -> Int {
    if !dosed.contains(day) { return 0 }
    var n = 1
    var d = try CalendarMath.addDays(day, -1)
    while dosed.contains(d) {
        n += 1
        d = try CalendarMath.addDays(d, -1)
    }
    return n
}

// MARK: - rhr_carried_over / vitals_present

/// True when the RHR shown was measured on an earlier day — the normal case,
/// since Garmin publishes no daily-summary row for the current day. Unknown
/// provenance (no `rhrDate`) counts as today's: absence of proof is not proof.
public nonisolated func rhrCarriedOver(_ m: MorningVitals, today: String) -> Bool {
    guard let date = m.rhrDate else { return false }
    return m.rhr != nil && date != today
}

/// True once Garmin has last night. RHR is deliberately NOT counted — it falls
/// back to yesterday's value, so it is present even on a night with no upload.
public nonisolated func vitalsPresent(_ m: MorningVitals) -> Bool {
    m.sleep != nil || m.hrv != nil
}

// MARK: - _fmt / _fmt_vs / vitals_line

/// `_fmt`: render a metric for human eyes. NEVER emit the literal string
/// `"None"` — a dict from `fetch_overnight` always HAS the key.
public nonisolated func fmtValue(_ v: Int?, suffix: String = "") -> String {
    guard let v else { return "?" }
    return "\(v)\(suffix)"
}

/// `_fmt` for an already-rendered value.
public nonisolated func fmtValue(_ v: String?, suffix: String = "") -> String {
    guard let v else { return "?" }
    return "\(v)\(suffix)"
}

/// `_fmt_vs`: render `"value/target"` (`"1748/1800"`) — `"?"` when unmeasured,
/// bare value when no target is known.
public nonisolated func fmtVs(_ v: Double?, goal: Double?, suffix: String = "") -> String {
    guard let v else { return "?" }
    guard let goal else { return "\(formatFixed(v, 0))\(suffix)" }
    return "\(formatFixed(v, 0))/\(formatFixed(goal, 0))\(suffix)"
}

/// `vitals_line`: the one-line overnight-vitals summary shown on the alert and
/// report (`"Sleep 85 (7.9h) · HRV 32 · RHR 61"`).
///
/// `sleepDurationH` is always rounded to one decimal upstream
/// (`fetch_overnight`), so `formatFixed(_, 1)` renders exactly what Python's
/// `str()` of that same rounded float gives, including the `"6.0"` case.
public nonisolated func vitalsLine(_ m: MorningVitals, today: String) -> String {
    var rhr = fmtValue(m.rhr)
    if rhrCarriedOver(m, today: today), let rhrDate = m.rhrDate {
        rhr += " (measured \(String(rhrDate.dropFirst(5))))"
    }
    let durStr = m.sleepDurationH.map { formatFixed($0, 1) }
    return "Sleep \(fmtValue(m.sleep)) (\(fmtValue(durStr, suffix: "h"))) · HRV \(fmtValue(m.hrv)) · RHR \(rhr)"
}

// MARK: - _streak / _best_streak

/// Current streak of `okDays` ending at (and including) `end`, walking
/// backwards day by day.
public nonisolated func streak(_ okDays: Set<String>, end: String) throws -> Int {
    var n = 0
    var d = end
    while okDays.contains(d) {
        n += 1
        d = try CalendarMath.addDays(d, -1)
    }
    return n
}

/// Longest run of consecutive dates anywhere in `okDays`. Order-independent (a
/// max reduction), so it is safe that Python iterates an unordered set here.
public nonisolated func bestStreak(_ okDays: Set<String>) throws -> Int {
    var best = 0
    for d in okDays {
        if okDays.contains(try CalendarMath.addDays(d, -1)) { continue }
        var n = 1
        var cur = try CalendarMath.addDays(d, 1)
        while okDays.contains(cur) {
            n += 1
            cur = try CalendarMath.addDays(cur, 1)
        }
        best = max(best, n)
    }
    return best
}

// MARK: - prev_from_state

/// Yesterday's gate flags — and ONLY yesterday's.
///
/// A same-day rerun keeps the `prev` already carried; anything older is
/// discarded, so a gap in runs can never pair two non-consecutive mornings into
/// a "2 consecutive mornings" trigger (audit A1).
public nonisolated func prevFromState(_ state: MorningGateState, today: String) throws -> MorningGatePrevState {
    guard let d = state.date else { return MorningGatePrevState() }
    if d == today { return state.prev ?? MorningGatePrevState() }
    if d == (try CalendarMath.addDays(today, -1)) {
        return MorningGatePrevState(
            hrvLow: state.hrvLow,
            rhrHigh: state.rhrHigh,
            rhrDate: state.rhrDate,
            sleepLow: state.sleepLow
        )
    }
    return MorningGatePrevState()
}

// MARK: - lift_flags

/// Returns `(reds, notes)` from benchmark-lift session history (newest session
/// first per lift, as `fetch_db` supplies it).
public nonisolated func liftFlags(
    _ lifts: [LiftHistory],
    config: MorningGateConfig = .default
) -> (reds: [String], notes: [String]) {
    var reds: [String] = []
    var notes: [String] = []
    for lift in lifts {
        let sessions = lift.sessions
        let label = pythonTitleCase(
            lift.name
                .replacingOccurrences(of: "BARBELL_", with: "")
                .replacingOccurrences(of: "_", with: " ")
        )
        if let first = sessions.first, let minReps = first.minReps, minReps >= config.progressionReps {
            notes.append(
                "\(label): all sets >= \(config.progressionReps) reps last session — +10 kg due "
                    + "(currently \(formatFixed(first.topKg, 0)) kg)."
            )
        }
        guard let first = sessions.first else { continue }
        let sameWeight = sessions.filter { $0.topKg == first.topKg }
        if sameWeight.count >= 3 {
            let v0 = sameWeight[0].volume
            let v1 = sameWeight[1].volume
            let v2 = sameWeight[2].volume
            if v0 < v1 && v1 < v2 {
                reds.append(
                    "\(label) volume down 2 sessions running "
                        + "(\(formatFixed(v2, 0)) -> \(formatFixed(v1, 0)) -> \(formatFixed(v0, 0)) kg-reps)"
                )
            }
        }
    }
    return (reds, notes)
}

// MARK: - _append_admin

/// Verdict-independent lines: the Friday weekly block and the DB-outage
/// warning. Called from BOTH the REDUCED early-return and the normal flow — a
/// 2026-08-05 review caught the early return silently dropping the Friday
/// weigh-in reminder and hiding a concurrent DB outage.
private nonisolated func appendAdmin(
    _ conditions: inout [String],
    today: String,
    db: MorningGateDb,
    config: MorningGateConfig
) throws {
    if try CalendarMath.isoWeekday(today) == config.weeklyBlockWeekday {
        conditions.append("WEEKLY: scale weigh-in (send composition screenshot) + tape waist measurement.")
        if let er = db.effRecent, let ep = db.effPrior {
            let pct = (er - ep) / ep * 100
            conditions.append(
                "Aerobic efficiency (speed/HR on easy runs): \(pyFloatStr(er)) vs \(pyFloatStr(ep)) prior 4wks "
                    + "(\(fmtSigned(pct, 1))% — \(pct >= 0 ? "improving" : "declining; deficit may be biting"))."
            )
        }
    }
    if !(db.dbOk ?? true) {
        conditions.append(
            "⚠ Database unavailable — nutrition, KPI, target AND the lift-decline trigger were NOT evaluated this morning."
        )
    }
}

// MARK: - evaluate

/// `evaluate(today, m, db, state) -> (verdict, conditions, new_state)`.
///
/// See the file header for the one documented signature deviation: the Python
/// function reads `scripts/dose_log.json` internally via `load_dose_log()`;
/// this port takes `dosedDates` as an explicit parameter instead.
public nonisolated func evaluate(
    today: String,
    vitals m: MorningVitals,
    db: MorningGateDb,
    state: MorningGatePrevState,
    dosedDates: [String] = [],
    config: MorningGateConfig = .default
) throws -> EvaluateResult {
    let session = try sessionFor(today)
    let sessionName = session.name
    let sessionType = session.type
    var conditions: [String] = []
    // Every figure below is read from the DB. If the sync failed they may be
    // partial, so EVERY derived line must carry the caveat — not just the KPIs.
    let stale = (db.stale ?? false) ? " ⚠ STALE (sync failed)" : ""
    // `zone_drift` is emitted first when present (morning_go.py ~L857). The RN
    // oracle has no such field; the Python source is L1's named ground truth.
    if let zoneDrift = m.zoneDrift, !zoneDrift.isEmpty { conditions.append(zoneDrift) }
    let sleep = m.sleep
    let hrv = m.hrv
    let rhr = m.rhr
    let dur = m.sleepDurationH

    // Garmin publishes no daily-summary row for the current day, so the freshest
    // RHR obtainable at report time is ALWAYS a day behind — see rhrCarriedOver.
    let rhrCarried = rhrCarriedOver(m, today: today)
    let hrvLowToday = m.hrvStatus == "LOW" || (hrv.map { $0 < 27 } ?? false)
    let rhrHighToday = rhr.map { $0 >= 66 } ?? false
    let sleepLowToday = sleep.map { $0 < 60 } ?? false
    let mRhrDate = m.rhrDate
    // Unknown provenance on either side counts as a distinct reading: absence of
    // a date cannot prove a repeat, and suppressing a red line needs proof.
    let sameRhrReading = mRhrDate != nil && mRhrDate == state.rhrDate
    let (liftReds, progressionNotes) = liftFlags(db.lifts, config: config)

    // Overnight metrics are NOT dose-artifacts and must never be exempted — the
    // HR offset is wake-gated (+0.6 bpm asleep), so HRV/RHR are real states.
    let dosedSet = Set(dosedDates)
    let doseDay = try consecutiveDoseIndex(today, dosed: dosedSet)

    var red: [String] = liftReds
    if hrvLowToday && (state.hrvLow ?? false) { red.append("HRV LOW 2 mornings") }
    if rhrHighToday && (state.rhrHigh ?? false) && !sameRhrReading { red.append("RHR >=66 2 mornings") }
    if sleepLowToday && (state.sleepLow ?? false) {
        red.append("sleep <60 two nights running (now \(fmtValue(sleep)))")
    }

    let newState = MorningGateNewState(
        date: today,
        hrvLow: hrvLowToday,
        rhrHigh: rhrHighToday,
        rhrDate: mRhrDate,
        sleepLow: sleepLowToday
    )

    if !red.isEmpty {
        // REDUCED, not a day off: a deload in actual programming practice is
        // reduced volume/intensity, never zero — full rest on every trigger is
        // the readiness-tool ratchet that killed trust in Whoop (audit B3/D1).
        let verdict = "REDUCED — deload dose, not a day off"
        conditions.append("Triggers: " + red.joined(separator: "; "))
        if sessionType == .interval {
            conditions.append(
                "NO 4x4. Easy Z2 30-40min (HR <=130) or walk — retry the quality session next slot."
            )
        } else if sessionType == .strength || sessionType == .optional {
            conditions.append(
                "Lift REDUCED: bench+row only, 3x6 at current weights, nothing to failure, no progression attempts, skip accessories. Then Z2 <=30min easy (HR <=130) or walk."
            )
        } else if sessionType == .z2 {
            conditions.append("Z2 REDUCED: 30-45min easy (HR <=130) max — or walk it.")
        } else {
            conditions.append("Rest day as planned — walks only.")
        }
        conditions.append("Eat maintenance today: ~2100-2200 kcal, protein \(config.proteinTarget)g.")
        var ill = false
        if let yResp = db.yResp, let respBase = db.respBaseline {
            ill = yResp >= respBase + config.respDeltaAmber
        }
        conditions.append(
            (ill
                ? "Respiration elevated vs baseline — if you feel ill, skip it all and walk (illness overrides the deload dose). "
                : "")
                + "Hard stop: chest anything, HR wildly high for pace, or feeling unwell -> walk only."
        )
        try appendAdmin(&conditions, today: today, db: db, config: config)
        return EvaluateResult(verdict: verdict, conditions: conditions, newState: newState)
    }

    var amberReasons: [String] = []
    if sleepLowToday {
        amberReasons.append("sleep \(fmtValue(sleep)) — a 2nd night <60 goes REDUCED")
    } else if let sleep, sleep < 70 {
        amberReasons.append("sleep \(sleep)")
    }
    if hrvLowToday { amberReasons.append("HRV \(fmtValue(hrv))") }
    if let rhr, rhr > 65 {
        if rhrCarried, let mRhrDate {
            amberReasons.append("RHR \(rhr) (measured \(String(mRhrDate.dropFirst(5))))")
        } else {
            amberReasons.append("RHR \(rhr)")
        }
    }
    if let dur, dur > 0, dur < config.minSleepH {
        amberReasons.append("only \(formatFixed(dur, 1))h sleep")
    }
    if let yResp = db.yResp, let respBase = db.respBaseline, yResp >= respBase + config.respDeltaAmber {
        amberReasons.append(
            "respiration \(formatFixed(yResp, 0)) vs baseline \(formatFixed(respBase, 0)) — possible incoming illness"
        )
    }
    // A metric that has not arrived is not a passing metric: the pre-wake run
    // fires before the watch uploads the night.
    if sleep == nil || hrv == nil { amberReasons.append("overnight vitals not synced yet") }
    let amber = !amberReasons.isEmpty

    let verdict: String
    if sessionType == .rest || sessionType == .optional {
        verdict = "REST day"
        conditions.append(
            "Walks only — \(formatThousands(config.stepTarget)) steps still on. Carbs can run lower (~120-140g)."
        )
        if sessionType == .optional {
            conditions.append(
                "Day 4 Full Upper is parked (no fixed weekday since 2026-08-30) — but if you do lift it, it counts."
            )
        }
    } else if sessionType == .interval {
        // Fails closed on sleep and HRV: both must be PRESENT and pass.
        var gateOk = (sleep.map { $0 >= 70 } ?? false)
            && (hrv.map { $0 >= 27 } ?? false)
            && (rhr.map { $0 <= 65 } ?? true)
            && (dur.map { $0 == 0 || $0 >= config.minSleepH } ?? true)
        // Day 3+ of consecutive dosing: amber counts as red for intervals only.
        if gateOk && doseDay >= 3 && amber {
            gateOk = false
            amberReasons.append("day \(doseDay) of consecutive dosing")
        }
        if gateOk {
            verdict = "GO — " + sessionName
            conditions.append(
                "Work reps capped at HR 175 (pace/RPE on dosed days). Carbs 160-190g, ALL 3h+ pre-run or after — nothing right before."
            )
        } else {
            verdict = "MODIFIED — swap intervals for easy Z2 30-40min"
            conditions.append(
                "Interval gate failed (" + amberReasons.joined(separator: ", ") + ") — retry the 4x4 next slot."
            )
        }
    } else {
        verdict = (amber ? "GO (auto-regulated) — " : "GO — ") + sessionName
        if sessionType == .z2 {
            conditions.append(
                (amber
                    ? "Amber (" + amberReasons.joined(separator: ", ") + "): cap the long run at ~45min easy, or walk it. "
                    : "Full long Z2 (easy, 116-138 or pace-based if dosed). ")
                    + "Steps target still applies either way."
            )
        } else if amber {
            conditions.append(
                "Amber (" + amberReasons.joined(separator: ", ")
                    + "): lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk."
            )
        } else {
            conditions.append(
                "Lift (~30min) + planned Z2 if treadmill is free (easy, 116-138 or pace-based if dosed); 30min is the floor while adjusting — walks cover whatever's missing."
            )
        }
    }

    // Weekly block + DB-outage warning sit high deliberately: the push truncates
    // at conditions[:9] (audit E3/D5, A2/E5).
    try appendAdmin(&conditions, today: today, db: db, config: config)

    conditions.append(contentsOf: progressionNotes)
    if let yk = db.yKcal, yk < 1500 {
        conditions.append(
            "Yesterday only \(formatFixed(yk, 0)) kcal — eat ~2000 today (still no food right before training)\(stale)."
        )
    } else if let yk = db.yKcal, yk > 2100 {
        conditions.append(
            "Yesterday \(formatFixed(yk, 0)) kcal (over target) — hold a clean \(config.kcalTarget) today\(stale)."
        )
    }
    if let yp = db.yProtein, yp < 150 {
        conditions.append(
            "Protein yesterday \(formatFixed(yp, 0))g — all 3 shakes today, target \(config.proteinTarget)g\(stale)."
        )
    }

    let daysSinceCutStart = try CalendarMath.diffDays(today, config.cutStart)
    if let trend = db.weightTrendWk, daysSinceCutStart >= 7 {
        if trend < -config.lossFastKgWk {
            conditions.append(
                "Losing \(formatFixed(abs(trend), 2)) kg/wk (too fast) — add ~200 kcal/day this week\(stale)."
            )
        } else if trend > -config.lossSlowKgWk {
            conditions.append(
                "Trend \(fmtSigned(trend, 2)) kg/wk (too slow) — check tracking gaps before cutting further\(stale)."
            )
        }
    }

    if let stepsY = m.stepsYesterday, stepsY < config.stepTarget {
        conditions.append(
            "Steps yesterday \(formatThousands(stepsY)) < \(formatThousands(config.stepTarget)) — plan walks earlier today."
        )
    }

    let yStr = try CalendarMath.addDays(today, -1)
    if dosedDates.contains(yStr) {
        let yIdx = try consecutiveDoseIndex(yStr, dosed: dosedSet)
        conditions.append(
            "Yesterday was DOSED (day \(yIdx) of the block) — Garmin OVERSTATES active kcal and intensity minutes badly: whole-day inflation measured at +34% to +800%, not the ~13% previously assumed (that figure was activity-level only). Discard TE/load; trust steps, distance, pace, sleep. Overnight HRV/RHR are NOT dose-affected — gates apply normally."
        )
    }

    if doseDay >= 3 {
        conditions.append(
            "Day \(doseDay) of consecutive dosing — ambient HR offset ~+29 bpm (vs +16 on day 1); today's Garmin intensity minutes and active kcal are largely phantom. Consider an undosed day before extending the block."
        )
    }

    let kpiDays = db.kpiDays ?? 0
    if let trackRate = db.trackRate {
        conditions.append(
            "KPI tracking: \(trackRate)% strict (day \(kpiDays) of cut, goal >=\(config.trackRateTarget)%) · "
                + "streak \(db.trackStreak ?? 0)d (best \(db.trackBest ?? 0)d)\(stale)."
        )
    }
    if let stepRate = db.stepRate {
        conditions.append(
            "KPI movement: \(stepRate)% days >=\(config.stepTarget / 1000)k steps · "
                + "streak \(db.stepStreak ?? 0)d (best \(db.stepBest ?? 0)d)\(stale)."
        )
    }
    if let exRate = db.exRate {
        conditions.append(
            "KPI exercise: \(exRate)% planned sessions done · "
                + "streak \(db.exStreak ?? 0)d (best \(db.exBest ?? 0)d)\(stale)."
        )
    }

    if let c3 = db.carbs3dAvg, c3 < Double(config.carb3dWatch) {
        conditions.append(
            "GLYCOGEN WATCH: 3-day carbs avg \(formatFixed(c3, 0))g (target \(config.carbTarget)g, floor \(config.carb3dWatch)g) — the low-carb drift is reflux-driven, not a choice, so patch with the SAFE list: rice/Milchreis, potatoes, banana, blueberries+honey, maltodextrin/dextrin in the shake. Front-load before ~15:00; grain-heavy sources stay off the menu."
        )
    }

    // The target comes from the active plan.gate_challenge row (fetch_db);
    // `gateExperimentTarget` only covers the legacy empty-table fallback. The RN
    // oracle additionally gates this block on `gateExperimentActive`, which has
    // been true for every golden.
    if config.gateExperimentActive, let experimentIntervals = db.experimentIntervals {
        let target = db.experimentTarget ?? config.gateExperimentTarget
        let nIv = min(experimentIntervals, target)
        let bar = String(repeating: "█", count: max(0, nIv)) + String(repeating: "░", count: max(0, target - nIv))
        conditions.append(
            "GATE EXPERIMENT [\(bar)] interval \(nIv)/\(target) — today's verdict is a PREDICTION, not a command: textbook plan runs regardless. Safety floor stands (HR ≤175, no sprints, symptom days exempt)."
        )
    }

    if let w = db.latestWeight {
        let span = config.baselineWeight - config.targetWeight
        let pct = max(0.0, min(100.0, (config.baselineWeight - w) / span * 100))
        let bfTxt: String
        if let bf = db.latestBf {
            bfTxt = " · BF \(formatFixed(bf, 1))% -> \(formatFixed(config.targetBf, 0))%"
        } else {
            bfTxt = " · BF target \(formatFixed(config.targetBf, 0))%"
        }
        conditions.append(
            "Target: \(formatFixed(w, 1)) -> \(pyFloatStr(config.targetWeight)) kg "
                + "(\(formatFixed(pct, 0))% of \(formatFixed(span, 1)) kg done)\(bfTxt)\(stale)."
        )
    }

    return EvaluateResult(verdict: verdict, conditions: conditions, newState: newState)
}
