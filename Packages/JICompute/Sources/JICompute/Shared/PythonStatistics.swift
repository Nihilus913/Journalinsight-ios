/// W-ONDEVICE O-2 — CPython 3.11 `statistics.mean` and `statistics.stdev` for floats, bit-exact.
///
/// CPython does not sum naively: `mean` sums the exact rationals (`float.as_integer_ratio`) and
/// rounds `total / n` once; `stdev` builds the exact sum of squared deviations and takes a
/// correctly rounded square root of that fraction (`_float_sqrt_of_frac`). A naive Swift sum is
/// off by an ulp often enough to flip `rolling < lower` on a flat baseline, so this reproduces the
/// exact arithmetic: every finite double is `m · 2^e`; sums are integers over a common `2^E`; the
/// final quotient / square root is computed to ≥ 60 bits with a sticky ("round to odd") bit and
/// then rounded once to a Double (`Double(UInt64)` rounds to nearest-even), which is the correctly
/// rounded result. Not valid for subnormal results (never reached by ln-RMSSD values).
public nonisolated enum PythonStatistics {
    /// `statistics.mean(values)`; `values` must be non-empty and finite.
    public static func mean(_ values: [Double]) -> Double {
        precondition(!values.isEmpty, "mean requires at least one data point")
        let (sum, negative, e) = exactSum(values)
        return roundedQuotient(sum, UInt64(values.count), exp2: e, negative: negative)
    }

    /// `statistics.stdev(values)` (sample, n − 1); `values` must have ≥ 2 finite elements.
    public static func stdev(_ values: [Double]) -> Double {
        precondition(values.count >= 2, "stdev requires at least two data points")
        let parts = values.map(decompose)
        let e = parts.filter { !$0.m.isZero }.map(\.e).min() ?? 0
        // n·Σx² − (Σx)², all over 2^(2E); always ≥ 0.
        var sxx = BinUInt.zero
        for p in parts where !p.m.isZero { sxx = sxx + (p.m * p.m).shiftedLeft(2 * (p.e - e)) }
        let (sx, _, _) = exactSum(values, commonExp: e)
        let n = UInt64(values.count)
        let num = sxx.multiplied(bySmall: n) - sx * sx
        return roundedSqrtQuotient(num, n * (n - 1), exp2: e)
    }

    // MARK: - exact pieces

    struct Part { let m: BinUInt; let e: Int; let negative: Bool }

    static func decompose(_ x: Double) -> Part {
        precondition(x.isFinite, "non-finite value")
        if x == 0 { return Part(m: .zero, e: 0, negative: false) }
        let bits = x.significandBitPattern
        let field = Int(x.exponentBitPattern)
        let m = field == 0 ? bits : bits | (1 << 52)
        let e = (field == 0 ? 1 : field) - 1075
        return Part(m: BinUInt(m), e: e, negative: x.sign == .minus)
    }

    /// |Σ values| as an integer over 2^E (E = the smallest exponent), and its sign.
    static func exactSum(_ values: [Double], commonExp: Int? = nil) -> (BinUInt, Bool, Int) {
        let parts = values.map(decompose)
        let e = commonExp ?? (parts.filter { !$0.m.isZero }.map(\.e).min() ?? 0)
        var pos = BinUInt.zero, neg = BinUInt.zero
        for p in parts where !p.m.isZero {
            let v = p.m.shiftedLeft(p.e - e)
            if p.negative { neg = neg + v } else { pos = pos + v }
        }
        return pos >= neg ? (pos - neg, false, e) : (neg - pos, true, e)
    }

    /// Correctly rounded (num / den) · 2^exp2.
    static func roundedQuotient(_ num: BinUInt, _ den: UInt64, exp2: Int, negative: Bool) -> Double {
        if num.isZero { return negative ? -0.0 : 0.0 }
        let s = 62 - (num.bitWidth - BinUInt(den).bitWidth)
        var sticky = false
        let scaled: BinUInt
        if s >= 0 { scaled = num.shiftedLeft(s) } else { let r = num.shiftedRight(-s); scaled = r.value; sticky = r.lost }
        let (q, rem) = scaled.divided(bySmall: den)
        var q64 = q.uint64Value
        if sticky || rem != 0 { q64 |= 1 }
        let mag = Double(q64) * pow2(exp2 - s)
        return negative ? -mag : mag
    }

    /// Correctly rounded sqrt(num / den) · 2^exp2.
    static func roundedSqrtQuotient(_ num: BinUInt, _ den: UInt64, exp2: Int) -> Double {
        if num.isZero { return 0 }
        // Choose an even shift 2t so that X = floor(num · 4^t / den) has ~122 bits.
        let t = (122 - (num.bitWidth - BinUInt(den).bitWidth)) / 2
        var sticky = false
        let scaled: BinUInt
        if t >= 0 { scaled = num.shiftedLeft(2 * t) } else { let r = num.shiftedRight(-2 * t); scaled = r.value; sticky = r.lost }
        let (x, rem) = scaled.divided(bySmall: den)
        let xv = x.uint128Value
        var a = isqrt(xv)
        if sticky || rem != 0 || UInt128(a) * UInt128(a) != xv { a |= 1 }
        return Double(a) * pow2(exp2 - t)
    }

    static func isqrt(_ x: UInt128) -> UInt64 {
        if x == 0 { return 0 }
        var a = UInt128(Double(x).squareRoot())
        // Newton then exact correction.
        for _ in 0..<4 where a > 0 { a = (a + x / a) / 2 }
        while a * a > x { a -= 1 }
        while (a + 1) * (a + 1) <= x { a += 1 }
        return UInt64(a)
    }

    static func pow2(_ k: Int) -> Double {
        // Exact power of two, split so huge |k| never overflows an intermediate.
        var r = 1.0, k = k
        while k > 1000 { r *= Double(sign: .plus, exponent: 1000, significand: 1); k -= 1000 }
        while k < -1000 { r *= Double(sign: .plus, exponent: -1000, significand: 1); k += 1000 }
        return r * Double(sign: .plus, exponent: k, significand: 1)
    }
}

/// Minimal arbitrary-precision unsigned binary integer (UInt32 limbs, little-endian, no trailing
/// zero limb) — only what `PythonStatistics` needs. `BigUInt` (decimal limbs) serves `PythonRound`.
nonisolated struct BinUInt: Sendable, Equatable, Comparable {
    private(set) var limbs: [UInt32]

    static let zero = BinUInt(limbs: [])

    private init(limbs: [UInt32]) {
        var l = limbs
        while let last = l.last, last == 0 { l.removeLast() }
        self.limbs = l
    }

    init(_ v: UInt64) { self.init(limbs: [UInt32(truncatingIfNeeded: v), UInt32(truncatingIfNeeded: v >> 32)]) }

    var isZero: Bool { limbs.isEmpty }

    var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    var uint64Value: UInt64 {
        precondition(limbs.count <= 2, "value exceeds 64 bits")
        var v: UInt64 = 0
        for (i, l) in limbs.enumerated() { v |= UInt64(l) << (32 * i) }
        return v
    }

    var uint128Value: UInt128 {
        precondition(limbs.count <= 4, "value exceeds 128 bits")
        var v: UInt128 = 0
        for (i, l) in limbs.enumerated() { v |= UInt128(l) << (32 * i) }
        return v
    }

    func shiftedLeft(_ k: Int) -> BinUInt {
        precondition(k >= 0)
        if isZero || k == 0 { return self }
        let words = k / 32, bits = k % 32
        var out = [UInt32](repeating: 0, count: words)
        var carry: UInt32 = 0
        for l in limbs {
            if bits == 0 { out.append(l) } else {
                out.append((l << bits) | carry)
                carry = l >> (32 - bits)
            }
        }
        if carry != 0 { out.append(carry) }
        return BinUInt(limbs: out)
    }

    /// floor(self / 2^k) and whether any 1-bit was shifted out.
    func shiftedRight(_ k: Int) -> (value: BinUInt, lost: Bool) {
        precondition(k >= 0)
        if k == 0 { return (self, false) }
        let words = k / 32, bits = k % 32
        if words >= limbs.count { return (.zero, !isZero) }
        var lost = limbs[0..<words].contains { $0 != 0 }
        if bits != 0 { lost = lost || (limbs[words] & ((1 << bits) - 1)) != 0 }
        var out: [UInt32] = []
        for i in words..<limbs.count {
            var v = limbs[i] >> bits
            if bits != 0, i + 1 < limbs.count { v |= limbs[i + 1] << (32 - bits) }
            out.append(v)
        }
        return (BinUInt(limbs: out), lost)
    }

    static func + (a: BinUInt, b: BinUInt) -> BinUInt {
        var out: [UInt32] = []
        var carry: UInt64 = 0
        for i in 0..<max(a.limbs.count, b.limbs.count) {
            let s = UInt64(i < a.limbs.count ? a.limbs[i] : 0) + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
            out.append(UInt32(truncatingIfNeeded: s))
            carry = s >> 32
        }
        if carry != 0 { out.append(UInt32(carry)) }
        return BinUInt(limbs: out)
    }

    /// a − b; requires a ≥ b.
    static func - (a: BinUInt, b: BinUInt) -> BinUInt {
        precondition(a >= b, "BinUInt underflow")
        var out: [UInt32] = []
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            var d = Int64(a.limbs[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
            if d < 0 { d += 1 << 32; borrow = 1 } else { borrow = 0 }
            out.append(UInt32(d))
        }
        return BinUInt(limbs: out)
    }

    static func * (a: BinUInt, b: BinUInt) -> BinUInt {
        if a.isZero || b.isZero { return .zero }
        var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            let ai = UInt64(a.limbs[i])
            for j in 0..<b.limbs.count {
                let t = ai * UInt64(b.limbs[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            var k = i + b.limbs.count
            while carry != 0 {
                let t = UInt64(out[k]) + carry
                out[k] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
                k += 1
            }
        }
        return BinUInt(limbs: out)
    }

    func multiplied(bySmall n: UInt64) -> BinUInt { self * BinUInt(n) }

    /// (floor(self / d), self mod d) for 0 < d < 2^32.
    func divided(bySmall d: UInt64) -> (BinUInt, UInt64) {
        precondition(d > 0 && d < (1 << 32), "divisor out of range")
        var out = [UInt32](repeating: 0, count: limbs.count)
        var rem: UInt64 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let cur = (rem << 32) | UInt64(limbs[i])
            out[i] = UInt32(cur / d)
            rem = cur % d
        }
        return (BinUInt(limbs: out), rem)
    }

    static func < (a: BinUInt, b: BinUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
            return a.limbs[i] < b.limbs[i]
        }
        return false
    }
}
