/// Bedtime-consistency metric (F6-3) — parity port of `app/vitals/bedtime.py`'s
/// rolling SD of sleep onset, transliterated from the RN oracle
/// `mobile/src/compute/sleepScore/bedtime.ts` (frozen v1.18.2).
///
/// Circadian regularity is a validated quality driver in its own right, not a
/// proxy for duration or score — grounded in Lunsford-Avery JR et al. (2018),
/// Sci Rep 8, 14158, DOI: 10.1038/s41598-018-32402-5, and the National Sleep
/// Foundation Sleep Timing and Variability Panel (2023), Sleep Health
/// 9(6):801-820, DOI: 10.1016/j.sleh.2023.07.016. This port reports raw SD in
/// minutes only — no verdict or gate logic, matching Python.
///
/// Python name                -> Swift name
/// ---------------------------------------------------
/// `MIN_NIGHTS`               -> `bedtimeMinNights`
/// `_onset_minutes`           -> `onsetMinutes` (internal)
/// `bedtime_consistency_sd_min` -> `bedtimeConsistencySdMin`
///
/// PARITY NOTE: onsets are `core.daily_sleep.sleep_start_local` — naive local
/// wall-clock values (`app/vitals/queries.py`); Python reads `.hour/.minute/
/// .second` with no timezone conversion at all. This port takes each onset as an
/// ISO `"YYYY-MM-DDTHH:MM:SS[.ffffff]"` string and reads those fields straight
/// out of the string, exactly like the TS oracle and for the same reason: any
/// `Date`/`Calendar` path would route the value through a timezone and could
/// disagree with the naive Python reading near a DST transition (and is banned
/// here anyway, XC `CLAUDE.md` rule 8). With no timezone math there is nothing
/// for a DST transition to perturb.
///
/// Golden fixture: `Resources/golden/sleep.golden.json` group `cases`,
/// `fn == "bedtimeConsistencySdMin"`.

/// A "spread" needs more than two points to mean anything — with 2 nights the
/// "SD" is just half of a single pairwise gap, not a distribution.
public let bedtimeMinNights = 3

/// Sleep-onset time-of-day is folded around noon (not midnight) before taking an
/// SD: typical bedtimes sit far from noon on the clock, so this avoids the
/// wraparound error a raw minutes-since-midnight SD would produce — e.g. 23:50
/// vs 00:10 is 20 minutes apart, not (unfolded) 940.
let bedtimeFoldAnchorMin = 12.0 * 60.0
let minutesPerDay = 24.0 * 60.0

/// Python's `%` is non-negative for a positive modulus; Swift's
/// `truncatingRemainder` is not, so fold it the way the TS oracle does.
nonisolated func pyMod(_ a: Double, _ m: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: m)
    return (r + m).truncatingRemainder(dividingBy: m)
}

/// Sleep-onset time-of-day as minutes from the noon fold anchor, in [0, 1440).
///
/// `ts` is a naive local `"YYYY-MM-DDTHH:MM:SS[.ffffff]"` string — the HH:MM:SS
/// fields are read directly; fractional seconds, if present, are ignored (Python
/// reads `ts.second`, a whole-second int, and never consults microseconds).
nonisolated func onsetMinutes(_ ts: String) throws -> Double {
    let s = Array(ts.utf8)
    guard s.count >= 19,
          s[10] == UInt8(ascii: "T"),
          s[13] == UInt8(ascii: ":"),
          s[16] == UInt8(ascii: ":")
    else { throw SleepComputeError.malformedOnsetTimestamp(ts) }

    func digits(_ range: Range<Int>) throws -> Int {
        var value = 0
        for i in range {
            let c = s[i]
            guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else {
                throw SleepComputeError.malformedOnsetTimestamp(ts)
            }
            value = value * 10 + Int(c - UInt8(ascii: "0"))
        }
        return value
    }
    let hour = try digits(11..<13)
    let minute = try digits(14..<16)
    let second = try digits(17..<19)

    let minutesOfDay = Double(hour) * 60.0 + Double(minute) + Double(second) / 60.0
    return pyMod(minutesOfDay - bedtimeFoldAnchorMin, minutesPerDay)
}

/// Sample SD (minutes) of sleep onset across the given nights.
///
/// Nights with a missing onset (`nil` — no `sleep_start_local` for that date,
/// e.g. an Apple-only day or a sync gap) are dropped, never fabricated or
/// interpolated. Degrades gracefully: the SD is computed over whatever onsets
/// remain, and the metric is absent (`nil`) once fewer than `bedtimeMinNights`
/// remain — never a misleadingly precise number from 1-2 points.
public nonisolated func bedtimeConsistencySdMin(_ onsetTimes: [String?]) throws -> Double? {
    let values = try onsetTimes.compactMap { $0 }.map(onsetMinutes)
    if values.count < bedtimeMinNights { return nil }

    let mean = values.reduce(0.0, +) / Double(values.count)
    let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    return pythonRound(variance.squareRoot(), 1)
}
