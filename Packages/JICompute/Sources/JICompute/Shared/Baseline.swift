/// W-ONDEVICE O-1 — the ONE causal median/MAD baseline primitive, shared by the recovery
/// personal normal (`PersonalNormal`), the sleep-debt baseline and the B-19 readiness composite.
/// Port of `app/vitals/readiness_composite.py` (`_median`, `robust_baseline`, `trailing_z`),
/// golden-tested bit-for-bit (`readiness.golden.json`). Constants are those of the gate design
/// spec (MIN_DAYS 19, WINDOW_DAYS 120, MAD 1.4826); `PersonalNormal` keeps its own 28-day window
/// and minN 14 (each path is ported as is, never unified silently) but uses the same arithmetic.
/// Dates are ISO `yyyy-MM-dd` strings; no ambient clock.
public nonisolated struct RobustBaseline: Hashable, Sendable {
    public let median: Double
    /// median(|v − median|) × `Baseline.madScale`.
    public let sd: Double

    public init(median: Double, sd: Double) { self.median = median; self.sd = sd }
}

public nonisolated enum Baseline {
    public static let minDays = 19
    public static let windowDays = 120
    public static let madScale = 1.4826

    /// Python `statistics.median` / `_median`: the middle value (odd n) or the float mean of the
    /// two middle values (even n). `values` must not be empty (Python raises there).
    public static func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty, "median of an empty list")
        let sorted = values.sorted()
        let n = sorted.count
        let mid = n / 2
        if n % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// (median, median(|v − median|) × madScale) with no count or zero-spread guard — the raw
    /// arithmetic every caller shares. `values` must not be empty.
    public static func medianMAD(_ values: [Double]) -> RobustBaseline {
        let med = median(values)
        return RobustBaseline(median: med, sd: median(values.map { abs($0 - med) }) * madScale)
    }

    /// nil below `minDays` values or when the spread is not positive (a flat window).
    public static func robustBaseline(_ values: [Double], minDays: Int = Baseline.minDays) -> RobustBaseline? {
        guard values.count >= minDays, !values.isEmpty else { return nil }
        let b = medianMAD(values)
        return b.sd > 0 ? b : nil
    }

    /// Causal z of `series[target]` against `[target − windowDays, target)` — today never enters
    /// its own baseline. nil when today has no value or the window misses `robustBaseline`.
    public static func trailingZ(target: String, series: [String: Double]) throws -> Double? {
        guard let value = series[target] else { return nil }
        let start = try CalendarMath.addDays(target, -windowDays)
        var window: [Double] = []
        for (d, v) in series where d >= start && d < target { window.append(v) }
        guard let b = robustBaseline(window) else { return nil }
        return (value - b.median) / b.sd
    }
}
