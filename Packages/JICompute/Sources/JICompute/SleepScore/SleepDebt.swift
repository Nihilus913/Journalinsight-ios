/// Personal sleep debt — parity port of `app/vitals/sleep_debt.py`,
/// transliterated from the RN oracle `mobile/src/compute/sleepScore/sleepDebt.ts`
/// (frozen v1.18.2). A rolling accumulated deficit against a baseline derived
/// from Toby's own unimpaired-night history (F6-2). See the Python module
/// docstring for the H1/H2 gate-compliance-experiment rationale this serves —
/// unchanged by the port, since both functions are already pure in Python.
///
/// Python name                     -> Swift name
/// ---------------------------------------------------------
/// `derive_personal_baseline_hours` -> `derivePersonalBaselineHours`
/// `compute_sleep_debt_series`      -> `computeSleepDebtSeries`
///
/// Golden fixture: `Resources/golden/sleep.golden.json` group `cases`,
/// `fn == "derivePersonalBaselineHours"` / `"computeSleepDebtSeries"`.

/// Personal sleep-need baseline: the median duration across Toby's own
/// "unimpaired" nights — not the generic 8h textbook figure.
///
/// "Unimpaired" is operationalized statistically, via Tukey's IQR fence
/// (Q1 - 1.5*IQR .. Q3 + 1.5*IQR) — LABELED AS CONVENTION (see the Python
/// docstring for the full reasoning: there is no illness/travel/symptom-day flag
/// in `core.*` to ground "impaired" directly). The MEDIAN of the fence-filtered
/// remainder is the baseline, not the mean, so a handful of still-included mild
/// outliers can't drag a single-number baseline toward them.
///
/// Returns `nil` when fewer than `minNights` nights are available — too little
/// history is a real "unknown"; callers must not silently substitute 8h.
public nonisolated func derivePersonalBaselineHours(
    _ durationHours: [Double],
    minNights: Int = 14
) -> Double? {
    if durationHours.count < minNights { return nil }

    if durationHours.count < 4 {
        // `quantilesInclusive` needs at least n=4 points for quartile
        // interpolation; `minNights` defaults well above this, but a caller
        // passing a lower `minNights` should still get a defined (if
        // degenerate) answer rather than an out-of-range read.
        return pythonRound(median(durationHours), 3)
    }

    let quartiles = quantilesInclusive(durationHours, n: 4)
    let q1 = quartiles[0]
    let q3 = quartiles[2]
    let iqr = q3 - q1
    let lo = q1 - 1.5 * iqr
    let hi = q3 + 1.5 * iqr
    var unimpaired = durationHours.filter { lo <= $0 && $0 <= hi }

    if unimpaired.isEmpty {
        // Degenerate (e.g. iqr == 0, every night identical) — every value is at
        // the fence boundary and should already have passed the <=/>=
        // comparison above; a defensive fallback, not an expected path.
        unimpaired = durationHours
    }

    return pythonRound(median(unimpaired), 3)
}

/// Rolling accumulated sleep deficit against `baselineHours`, in hours.
///
/// For each night, sums `baselineHours - durationHours` over the trailing
/// `windowDays` calendar days (inclusive of the night itself) among the nights
/// actually present in `nights` — a night with no data in that span is excluded
/// from the sum, not zero-filled, since a missing night is unknown rather than a
/// zero deficit. `nightsInWindow` records how many nights actually contributed.
///
/// `debtHours` can go negative — a stretch of nights above baseline is a real
/// surplus, not clamped to zero, which is what lets a rebound run show up as
/// debt draining back down.
///
/// `nights` need not be pre-sorted; this sorts a copy. Requires one row per date
/// — behavior is undefined if the same date appears twice (the Python contract).
/// Throws if a night's `date` is not a well-formed ISO `"YYYY-MM-DD"` string.
public nonisolated func computeSleepDebtSeries(
    _ nights: [NightlySleep],
    baselineHours: Double,
    windowDays: Int = 14
) throws -> [SleepDebtDay] {
    // ISO "YYYY-MM-DD" strings order lexicographically exactly as the Python
    // `datetime.date` objects order chronologically.
    let ordered = nights.sorted { $0.date < $1.date }
    var result: [SleepDebtDay] = []

    for night in ordered {
        let windowStart = try CalendarMath.addDays(night.date, -(windowDays - 1))
        let windowNights = ordered.filter { windowStart <= $0.date && $0.date <= night.date }
        var debt = 0.0
        for n in windowNights { debt += baselineHours - n.durationHours }
        result.append(SleepDebtDay(
            date: night.date,
            durationHours: night.durationHours,
            baselineHours: baselineHours,
            debtHours: pythonRound(debt, 2),
            nightsInWindow: windowNights.count
        ))
    }

    return result
}
