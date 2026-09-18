/// Sleep score computed from stage data — parity port of
/// `app/vitals/sleep_score.py::compute_sleep_score`, transliterated from the RN
/// oracle `mobile/src/compute/sleepScore/sleepScore.ts` (frozen v1.18.2).
///
/// Shadow-mode field, not a gate input (see the Python module docstring) — this
/// port carries only the pure arithmetic; `backfill_sleep_score_computed`
/// (DB I/O) is NOT ported.
///
/// Python name         -> Swift name
/// ---------------------------------------
/// `_ramp`             -> `sleepRamp` (internal)
/// `compute_sleep_score` -> `computeSleepScore`
///
/// Component weights (sum 100) and target ratios are grounded in
/// `docs/research/sleep-score-components.md`; they must stay byte-identical to
/// the Python module.
///
/// Golden fixture: `Resources/golden/sleep.golden.json` group `cases`,
/// `fn == "computeSleepScore"`.

let sleepTargetSec = 8.0 * 3600.0
let sleepMinSec = 4.0 * 3600.0
/// Convention midpoint of Ohayon 2004's ~13-23% N3 range.
let sleepDeepTarget = 0.18
/// Convention midpoint of Ohayon 2004's 20-25% REM range.
let sleepRemTarget = 0.225

/// Linear 0..1 ramp; clamped outside `[low, high]`.
nonisolated func sleepRamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    if high <= low { return 0.0 }
    return max(0.0, min(1.0, (value - low) / (high - low)))
}

/// Return 0-100, or `nil` when there is no duration to score.
///
/// Missing stage data (common on Apple-only nights) scores each affected
/// component at 80% of its weight rather than 0% — a missing breakdown is
/// absence of data, not evidence of bad architecture, and penalising it would
/// make every Apple-only night look worse than it was (CONVENTION,
/// `docs/research/sleep-score-components.md`).
///
/// Mirrors Python's falsy guard exactly: a `nil`, `0` or negative duration is
/// unscoreable.
public nonisolated func computeSleepScore(
    durationSec: Int?,
    deepSec: Int?,
    remSec: Int?,
    awakeSec: Int?
) -> Int? {
    guard let durationSec, durationSec > 0 else { return nil }
    let duration = Double(durationSec)

    let durationPts = 50.0 * sleepRamp(duration, sleepMinSec, sleepTargetSec)

    let deepPts = deepSec.map { 20.0 * min(1.0, (Double($0) / duration) / sleepDeepTarget) } ?? 20.0 * 0.8
    let remPts = remSec.map { 20.0 * min(1.0, (Double($0) / duration) / sleepRemTarget) } ?? 20.0 * 0.8
    let contPts = awakeSec.map { 10.0 * (1.0 - sleepRamp(Double($0) / duration, 0.05, 0.25)) } ?? 10.0 * 0.8

    return Int(pythonRound(durationPts + deepPts + remPts + contPts, 0))
}
