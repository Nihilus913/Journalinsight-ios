import Foundation

/// Verdict-string builders: the small formatting helpers the morning gate needs
/// to render Python f-strings byte for byte.
///
/// Every one of these exists because a Python format spec has no Swift
/// equivalent that agrees on the edge cases. Foundation's printf-style string
/// formatter is banned in `JICompute` (XC `CLAUDE.md` rule 8 / W6 card) —
/// `formatFixed` in `Shared/PythonRound.swift` is the only sanctioned decimal
/// formatter, and everything here is built on it.

/// Python `f"{n:,}"` thousands-grouping, for the integer counts this module
/// formats that way (`steps_yesterday`, `STEP_TARGET`).
nonisolated func formatThousands(_ n: Int) -> String {
    let digits = String(n.magnitude)
    var grouped = ""
    for (index, character) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 { grouped.append(",") }
        grouped.append(character)
    }
    return n < 0 ? "-" + grouped : grouped
}

/// Python `f"{v:+.nf}"`: always-signed fixed decimal, built on `formatFixed` so
/// ties-to-even and the `-0.0` sign are preserved exactly as Python renders them.
nonisolated func fmtSigned(_ v: Double, _ n: Int) -> String {
    let s = formatFixed(v, n)
    return s.hasPrefix("-") ? s : "+" + s
}

/// Python `str(float)` for a BARE (non `":.nf"`) f-string interpolation of a
/// value that is conceptually a float.
///
/// Swift's `Double` description is the same shortest-round-trip rendering as
/// Python's `repr`, including the trailing `".0"` on a whole number and the
/// sign on `-0.0`, and it switches to exponent form at the same magnitudes.
/// Used only where `evaluate()`/`appendAdmin` bare-interpolate a genuine Python
/// float: `eff_recent`/`eff_prior` (~0.8-2.5) and `TARGET_WEIGHT` (68.5).
nonisolated func pyFloatStr(_ v: Double) -> String {
    "\(v)"
}

/// Python `str.title()`: each maximal run of ASCII letters gets its first
/// character uppercased and the rest lowercased; any non-letter resets the word
/// boundary. (CPython's actual algorithm — general enough for any future
/// benchmark-lift name, not just the two `benchmarkLifts` constants.)
nonisolated func pythonTitleCase(_ s: String) -> String {
    var out = ""
    var previousWasCased = false
    for character in s {
        if character.isASCII && character.isLetter {
            out += previousWasCased ? character.lowercased() : character.uppercased()
            previousWasCased = true
        } else {
            out.append(character)
            previousWasCased = false
        }
    }
    return out
}
