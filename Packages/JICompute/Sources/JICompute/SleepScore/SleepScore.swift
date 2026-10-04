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
/// `compute_sleep_score_breakdown` -> `computeSleepScoreBreakdown` (W-B67 R-2)
/// `_components`       -> `sleepComponents` (internal)
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

/// One scored component of the sleep score (W-B67 R-2) — same shape as the hub's
/// `compute_sleep_score_breakdown` component dict. `points` is rounded to 1 dp, `share` (ratio
/// of sleep time) to 3 dp; `inferred` = the stage was missing and credited at 80 %.
public struct ComputedSleepComponent: Sendable, Equatable {
    public let key: String          // duration | deep | rem | continuity
    public let points: Double
    public let max: Int
    public let value: Int?
    public let share: Double?
    public let target: Double?
    public let inferred: Bool

    public init(key: String, points: Double, max: Int, value: Int?, share: Double?, target: Double?, inferred: Bool) {
        self.key = key; self.points = points; self.max = max; self.value = value
        self.share = share; self.target = target; self.inferred = inferred
    }
}

/// The breakdown: `total` is rounded from the UNROUNDED sum, so it always equals
/// `computeSleepScore`; the 1-dp `points` may sum to `total` ± 0.2.
public struct ComputedSleepBreakdown: Sendable, Equatable {
    public let total: Int
    public let components: [ComputedSleepComponent]
}

/// The four components with unrounded points — the ONE arithmetic both `computeSleepScore` and
/// `computeSleepScoreBreakdown` read (mirrors Python's `_components`).
private nonisolated func sleepComponents(
    _ duration: Double, deepSec: Int?, remSec: Int?, awakeSec: Int?
) -> [(raw: Double, ComputedSleepComponent)] {
    func comp(_ key: String, _ raw: Double, _ max: Int, _ value: Int?, _ share: Double?, _ target: Double?, _ inferred: Bool)
        -> (raw: Double, ComputedSleepComponent) {
        (raw, ComputedSleepComponent(key: key, points: pythonRound(raw, 1), max: max, value: value,
                                     share: share.map { pythonRound($0, 3) }, target: target, inferred: inferred))
    }
    func stage(_ key: String, _ value: Int?, _ weight: Int, _ target: Double) -> (raw: Double, ComputedSleepComponent) {
        guard let value else { return comp(key, Double(weight) * 0.8, weight, nil, nil, target, true) }
        let share = Double(value) / duration
        return comp(key, Double(weight) * min(1.0, share / target), weight, value, share, target, false)
    }
    let continuity: (raw: Double, ComputedSleepComponent)
    if let awakeSec {
        let share = Double(awakeSec) / duration
        continuity = comp("continuity", 10.0 * (1.0 - sleepRamp(share, 0.05, 0.25)), 10, awakeSec, share, nil, false)
    } else {
        continuity = comp("continuity", 10.0 * 0.8, 10, nil, nil, nil, true)
    }
    return [
        comp("duration", 50.0 * sleepRamp(duration, sleepMinSec, sleepTargetSec), 50, Int(duration), nil, nil, false),
        stage("deep", deepSec, 20, sleepDeepTarget),
        stage("rem", remSec, 20, sleepRemTarget),
        continuity,
    ]
}

/// Per-component breakdown of `computeSleepScore` (W-B67 R-2, parity with the hub's
/// `compute_sleep_score_breakdown`). `nil` exactly when `computeSleepScore` is `nil`.
/// Display only — shadow score, not a gate input.
public nonisolated func computeSleepScoreBreakdown(
    durationSec: Int?,
    deepSec: Int?,
    remSec: Int?,
    awakeSec: Int?
) -> ComputedSleepBreakdown? {
    guard let durationSec, durationSec > 0 else { return nil }
    let comps = sleepComponents(Double(durationSec), deepSec: deepSec, remSec: remSec, awakeSec: awakeSec)
    // Sum in the same left-to-right order as Python's `sum()` (0.0 start) — bit-identical.
    let total = Int(pythonRound(comps.reduce(0.0) { $0 + $1.raw }, 0))
    return ComputedSleepBreakdown(total: total, components: comps.map(\.1))
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
/// unscoreable. Built on `computeSleepScoreBreakdown` — one arithmetic (W-B67).
public nonisolated func computeSleepScore(
    durationSec: Int?,
    deepSec: Int?,
    remSec: Int?,
    awakeSec: Int?
) -> Int? {
    computeSleepScoreBreakdown(durationSec: durationSec, deepSec: deepSec, remSec: remSec, awakeSec: awakeSec)?.total
}
