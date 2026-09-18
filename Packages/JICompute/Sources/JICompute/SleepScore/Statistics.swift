/// CPython `statistics` helpers needed by the sleep-debt baseline.
///
/// Transliterated from the RN oracle `mobile/src/compute/shared/statistics.ts`
/// (frozen v1.18.2), which in turn reproduces CPython `Lib/statistics.py`
/// exactly — not merely "a" median/quantile implementation — because the
/// results are golden-tested against the live Python output.
///
/// Internal, not public: only `derivePersonalBaselineHours` consumes them, and
/// `Shared/*` is frozen after W6-L0, so they live with their one caller.

/// Python's `statistics.median()`: sort, then the single middle value (odd n)
/// or the arithmetic mean of the two middle values (even n, float division).
nonisolated func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let n = sorted.count
    let mid = n / 2
    if n % 2 == 1 { return sorted[mid] }
    return (sorted[mid - 1] + sorted[mid]) / 2
}

/// Python's `statistics.quantiles(data, n: n, method: "inclusive")`: the n-1
/// cut points dividing sorted data into n equal-probability intervals,
/// interpolating inclusive of the endpoints.
///
/// CPython algorithm (`Lib/statistics.py`, `method="inclusive"`):
///     m = ld - 1
///     for i in range(1, n):
///         j, delta = divmod(i * m, n)
///         interpolated = (data[j] * (n - delta) + data[j + 1] * delta) / n
///
/// Requires `data.count >= 2` (Python raises `StatisticsError` below that);
/// the only caller guards with `count >= 4` itself.
nonisolated func quantilesInclusive(_ data: [Double], n: Int = 4) -> [Double] {
    let sorted = data.sorted()
    let m = sorted.count - 1
    var result: [Double] = []
    for i in 1..<n {
        let total = i * m
        let j = total / n
        let delta = total - j * n
        let interpolated = (sorted[j] * Double(n - delta) + sorted[j + 1] * Double(delta)) / Double(n)
        result.append(interpolated)
    }
    return result
}
