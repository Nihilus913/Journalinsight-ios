/// Python-parity rounding and fixed-point formatting.
///
/// Transliterated from the RN oracle `mobile/src/compute/shared/round.ts`
/// (frozen v1.18.2), verified against the Python-generated goldens in
/// `shared.golden.json`.
///
/// The compute ports are PARITY ports: they must reproduce the Python
/// pipeline's numbers to the decimal (spec: 2026-08-23-ts-compute-parity-port).
/// Python's `round()` and `f"{x:.nf}"` round the EXACT binary value of the
/// double with ties-to-even. Swift's `rounded()` rounds half away from zero and
/// `String(format: "%.2f")` goes through the C library's own (locale-sensitive,
/// and for `%.nf` correctly-rounded-but-differently-tied) path, so neither can
/// be used here. We reproduce Python by extracting the double's exact decimal
/// expansion via `BigUInt` — every finite double has one — and rounding that.
///
/// Deliberately free of `Foundation`: no `NumberFormatter`, no `String(format:)`,
/// no `Locale`. The output of `formatFixed` is byte-identical on every device.

/// `|value| == d * 10^e` exactly; `d == 0` for ±0. `sign` is ±1 and is carried
/// separately so that −0.0 survives the round trip.
nonisolated struct ExactDecimal: Sendable, Equatable {
    var sign: Int
    var d: BigUInt
    var e: Int
}

/// Decompose a finite `Double` into its exact decimal expansion.
nonisolated func exactDecimal(_ value: Double) -> ExactDecimal {
    let bits = value.bitPattern
    let sign = (bits >> 63) != 0 ? -1 : 1
    let expBits = Int((bits >> 52) & 0x7ff)
    let mantBits = bits & ((UInt64(1) << 52) - 1)
    // |value| == m * 2^e2
    let m = expBits == 0 ? mantBits : mantBits | (UInt64(1) << 52)
    let e2 = expBits == 0 ? -1074 : expBits - 1075
    if m == 0 { return ExactDecimal(sign: sign, d: .zero, e: 0) }
    if e2 >= 0 { return ExactDecimal(sign: sign, d: BigUInt(m).multiplied(byPowerOfTwo: e2), e: 0) }
    // m * 2^e2 == (m * 5^-e2) * 10^e2
    return ExactDecimal(sign: sign, d: BigUInt(m).multiplied(byPowerOfFive: -e2), e: e2)
}

/// Divide by `10^k` with ties-to-even (`k >= 1`).
nonisolated func halfEvenDiv(_ d: BigUInt, _ k: Int) -> BigUInt {
    precondition(k >= 1, "halfEvenDiv requires k >= 1")
    let (quotient, remainder) = d.divided(byPowerOfTen: k)
    // half == 10^k / 2 == 5 * 10^(k-1), exact for every k >= 1.
    var half = BigUInt.powerOfTen(k - 1)
    half.multiply(by: 5)
    if remainder > half || (remainder == half && quotient.isOdd) { return quotient.incremented() }
    return quotient
}

/// Powers of ten that are exactly representable as `Double` (10^0 … 10^22).
private let exactPowersOfTen: [Double] = {
    var result: [Double] = [1]
    var v: Double = 1
    for _ in 1...22 {
        v *= 10
        result.append(v)
    }
    return result
}()

/// `10^n` as a `Double`, exact for `0 <= n <= 22` — the only range the parity
/// ports use. Mirrors JS `Math.pow(10, n)` on that range.
private func pow10Double(_ n: Int) -> Double {
    if n >= 0 && n < exactPowersOfTen.count { return exactPowersOfTen[n] }
    var v: Double = 1
    for _ in 0..<n { v *= 10 }
    return v
}

/// Python `round(value, ndigits)`.
///
/// `ndigits` omitted/0 matches Python's integer-returning `round(value)` (so
/// `-0.4` → `0`, not `-0.0`). With `ndigits > 0` the sign of a negative-zero
/// result is preserved, as Python does (`round(-0.04, 1) == -0.0`).
public nonisolated func pythonRound(_ value: Double, _ ndigits: Int = 0) -> Double {
    if !value.isFinite { return value }
    let exact = exactDecimal(value)
    let k = -(exact.e + ndigits)
    if k <= 0 {
        // Already exact at this precision — but ndigits == 0 must mirror
        // Python's int-returning round(): round(-0.0) is 0, never -0.0.
        return ndigits == 0 && value == 0 ? 0 : value
    }
    let q = halfEvenDiv(exact.d, k)
    var result: Double
    if ndigits > 0 {
        result = q.doubleValue / pow10Double(ndigits) // single correctly-rounded op
    } else if ndigits < 0 {
        result = q.doubleValue * pow10Double(-ndigits)
    } else {
        result = q.doubleValue
    }
    if exact.sign < 0 { result = -result }
    // Python round(x) with ndigits omitted returns an int — never -0.0.
    if ndigits == 0 && result == 0 { return 0 }
    return result
}

/// Python `f"{value:.<ndigits>f}"` — fixed decimals, ties-to-even on the exact
/// binary value, `"-0.0"` preserved for negative values that round to zero.
public nonisolated func formatFixed(_ value: Double, _ ndigits: Int) -> String {
    precondition(ndigits >= 0, "formatFixed requires ndigits >= 0")
    if !value.isFinite {
        if value == .infinity { return "inf" }
        if value == -.infinity { return "-inf" }
        return "nan"
    }
    let exact = exactDecimal(value)
    let k = -(exact.e + ndigits)
    let q = k <= 0 ? exact.d.multiplied(byPowerOfTen: -k) : halfEvenDiv(exact.d, k)
    let prefix = exact.sign < 0 ? "-" : ""
    if ndigits == 0 { return prefix + q.decimalString }
    let (intPart, fracPart) = q.divided(byPowerOfTen: ndigits)
    let frac = fracPart.decimalString
    let padded = String(repeating: "0", count: max(0, ndigits - frac.count)) + frac
    return prefix + intPart.decimalString + "." + padded
}
