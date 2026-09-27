/// B-57 W3 — the 28-day personal normal: median ± 1.4826·MAD over the 28 days before the 7-day
/// window (today−34 … today−7). Port of `app/vitals/recovery_score.py` (`personal_normal`,
/// `normal_count`, `window_mean`), golden-tested (`recovery.golden.json`). Display-only (spec §3.2).
/// Every sum runs in ascending ISO-date order, like the Python. Dates are ISO `yyyy-MM-dd`
/// strings (lexicographic order = date order); no ambient clock — `today` is always passed in.
public nonisolated struct PersonalNormalResult: Hashable, Sendable, Codable {
    public let median: Double
    public let low: Double
    public let high: Double
    public let sd: Double
    public let n: Int

    public init(median: Double, low: Double, high: Double, sd: Double, n: Int) {
        self.median = median; self.low = low; self.high = high; self.sd = sd; self.n = n
    }

    public var range: ClosedRange<Double> { low...high }
}

public nonisolated enum PersonalNormal {
    public static let windowDays = 7
    public static let normalDays = 28
    public static let minN = 14
    public static let madScale = 1.4826

    /// The 28 days before the 7-day window: today−34 … today−7, inclusive.
    public static func window(today: String) throws -> (start: String, end: String) {
        (try CalendarMath.addDays(today, -(windowDays + normalDays - 1)), try CalendarMath.addDays(today, -windowDays))
    }

    static func values(_ series: [String: Double], today: String) throws -> [Double] {
        let (start, end) = try window(today: today)
        var out: [Double] = []
        for key in series.keys.sorted() where key >= start && key <= end {
            if let v = series[key], v.isFinite { out.append(v) }
        }
        return out
    }

    public static func count(_ series: [String: Double], today: String) throws -> Int {
        try values(series, today: today).count
    }

    /// nil below `minN` values (Calibrating) — never a guessed band.
    public static func normal(_ series: [String: Double], today: String, minN: Int = PersonalNormal.minN) throws -> PersonalNormalResult? {
        let vals = try values(series, today: today)
        guard !vals.isEmpty, vals.count >= minN else { return nil }
        let med = median(vals)
        let sd = median(vals.map { abs($0 - med) }) * madScale
        return PersonalNormalResult(median: med, low: med - sd, high: med + sd, sd: sd, n: vals.count)
    }

    /// Mean of the finite values in today−6 … today, or nil when there are none.
    public static func windowMean(_ series: [String: Double], today: String) throws -> Double? {
        let start = try CalendarMath.addDays(today, -(windowDays - 1))
        var total = 0.0
        var n = 0
        for key in series.keys.sorted() where key >= start && key <= today {
            if let v = series[key], v.isFinite { total += v; n += 1 }
        }
        return n == 0 ? nil : total / Double(n)
    }
}
