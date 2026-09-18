/// Arbitrary-precision unsigned integer, stored as base-10^9 limbs.
///
/// This is the Swift stand-in for the JS `BigInt` the TypeScript oracle
/// (`mobile/src/compute/shared/round.ts`) uses to expand a `Double` into its
/// EXACT decimal value. `Int128` is not enough: the exact decimal expansion of
/// a subnormal double needs `m * 5^1074` — roughly 751 decimal digits — and
/// the divisor `10^k` can be just as wide.
///
/// The limb base is decimal (10^9) rather than a power of two on purpose:
/// every operation `PythonRound` needs is a decimal one (divide by 10^k,
/// compare against 5·10^(k-1), render digits), and a decimal base makes those
/// limb shifts instead of long division.
///
/// Limbs are little-endian (`limbs[0]` is the least significant) and carry no
/// trailing zero limb; the empty array is zero.
nonisolated struct BigUInt: Sendable, Equatable, Comparable {
    /// 10^9 — the largest power of ten whose square still leaves room for a
    /// full `UInt32` multiplier inside `UInt64`.
    static let base: UInt64 = 1_000_000_000
    static let baseDigits = 9

    private(set) var limbs: [UInt32]

    private init(normalizing limbs: [UInt32]) {
        var l = limbs
        while let last = l.last, last == 0 { l.removeLast() }
        self.limbs = l
    }

    init(_ value: UInt64) {
        var v = value
        var l: [UInt32] = []
        while v > 0 {
            l.append(UInt32(v % Self.base))
            v /= Self.base
        }
        self.limbs = l
    }

    static let zero = BigUInt(0)

    var isZero: Bool { limbs.isEmpty }

    /// True when the value is odd. A base-10^9 number's parity is the parity of
    /// its lowest limb: 10^9 is even, so every higher limb contributes an even
    /// amount.
    var isOdd: Bool { (limbs.first ?? 0) % 2 == 1 }

    // MARK: - Comparison

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) where lhs.limbs[i] != rhs.limbs[i] {
            return lhs.limbs[i] < rhs.limbs[i]
        }
        return false
    }

    // MARK: - Arithmetic

    /// Multiply in place by a single-word factor.
    ///
    /// `limb * factor + carry` is at most (10^9 − 1)·(2^32 − 1) + carry ≈
    /// 4.3·10^18, comfortably inside `UInt64`.
    mutating func multiply(by factor: UInt32) {
        if factor == 0 { limbs = []; return }
        if limbs.isEmpty { return }
        var carry: UInt64 = 0
        for i in limbs.indices {
            let product = UInt64(limbs[i]) * UInt64(factor) + carry
            limbs[i] = UInt32(product % Self.base)
            carry = product / Self.base
        }
        while carry > 0 {
            limbs.append(UInt32(carry % Self.base))
            carry /= Self.base
        }
    }

    mutating func add(_ addend: UInt32) {
        var carry = UInt64(addend)
        var i = 0
        while carry > 0 {
            if i == limbs.count { limbs.append(0) }
            let sum = UInt64(limbs[i]) + carry
            limbs[i] = UInt32(sum % Self.base)
            carry = sum / Self.base
            i += 1
        }
    }

    func incremented() -> BigUInt {
        var copy = self
        copy.add(1)
        return copy
    }

    /// `self * 2^exponent`, done in 30-bit chunks so each step is one
    /// `multiply(by:)`.
    func multiplied(byPowerOfTwo exponent: Int) -> BigUInt {
        precondition(exponent >= 0, "negative power of two")
        var result = self
        var remaining = exponent
        while remaining >= 30 {
            result.multiply(by: 1 << 30)
            remaining -= 30
        }
        if remaining > 0 { result.multiply(by: UInt32(1) << UInt32(remaining)) }
        return result
    }

    /// `self * 5^exponent`, done in chunks of 5^13 = 1_220_703_125 (< 2^31).
    func multiplied(byPowerOfFive exponent: Int) -> BigUInt {
        precondition(exponent >= 0, "negative power of five")
        var result = self
        var remaining = exponent
        while remaining >= 13 {
            result.multiply(by: 1_220_703_125)
            remaining -= 13
        }
        if remaining > 0 { result.multiply(by: Self.pow5Word(remaining)) }
        return result
    }

    private static func pow5Word(_ exponent: Int) -> UInt32 {
        precondition(exponent >= 0 && exponent < 13)
        var v: UInt32 = 1
        for _ in 0..<exponent { v *= 5 }
        return v
    }

    /// `self * 10^exponent` — a whole-limb shift plus one small multiply.
    func multiplied(byPowerOfTen exponent: Int) -> BigUInt {
        precondition(exponent >= 0, "negative power of ten")
        if isZero { return self }
        let limbShift = exponent / Self.baseDigits
        let digitShift = exponent % Self.baseDigits
        var result = BigUInt(normalizing: Array(repeating: 0, count: limbShift) + limbs)
        if digitShift > 0 { result.multiply(by: Self.pow10Word(digitShift)) }
        return result
    }

    static func powerOfTen(_ exponent: Int) -> BigUInt {
        BigUInt(1).multiplied(byPowerOfTen: exponent)
    }

    private static func pow10Word(_ exponent: Int) -> UInt32 {
        precondition(exponent >= 0 && exponent < baseDigits)
        var v: UInt32 = 1
        for _ in 0..<exponent { v *= 10 }
        return v
    }

    /// Exact division by `10^exponent`, returning quotient and remainder.
    func divided(byPowerOfTen exponent: Int) -> (quotient: BigUInt, remainder: BigUInt) {
        precondition(exponent >= 0, "negative power of ten")
        if exponent == 0 { return (self, .zero) }
        let limbShift = exponent / Self.baseDigits
        let digitShift = exponent % Self.baseDigits

        if limbShift >= limbs.count {
            // The whole value is below the divisor.
            return (.zero, self)
        }
        let low = Array(limbs.prefix(limbShift))
        var high = Array(limbs.dropFirst(limbShift))

        var carry: UInt64 = 0
        if digitShift > 0 {
            let divisor = UInt64(Self.pow10Word(digitShift))
            for i in stride(from: high.count - 1, through: 0, by: -1) {
                let cur = carry * Self.base + UInt64(high[i])
                high[i] = UInt32(cur / divisor)
                carry = cur % divisor
            }
        }
        // carry < 10^digitShift <= 10^8 < base, so it fits in one limb.
        let remainderLimbs = low + [UInt32(carry)]
        return (BigUInt(normalizing: high), BigUInt(normalizing: remainderLimbs))
    }

    // MARK: - Rendering

    var decimalString: String {
        guard let most = limbs.last else { return "0" }
        var out = String(most)
        for i in stride(from: limbs.count - 2, through: 0, by: -1) {
            let chunk = String(limbs[i])
            out += String(repeating: "0", count: Self.baseDigits - chunk.count) + chunk
        }
        return out
    }

    /// Correctly-rounded conversion to `Double` — the Swift equivalent of JS
    /// `Number(bigint)`. Going through the decimal string keeps the single
    /// correctly-rounded step the parity port depends on; `Double(String)` is
    /// specified to round to nearest-even.
    var doubleValue: Double {
        Double(decimalString) ?? .infinity
    }
}
