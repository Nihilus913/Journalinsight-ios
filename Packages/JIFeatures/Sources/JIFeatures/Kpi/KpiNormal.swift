import Foundation
import JICompute
import JIDesign

/// B-57 W3 S2 — the 28-day personal normal of whatever series a screen already plots
/// (display-only; `PersonalNormal`: median ± 1.4826·MAD over today−34 … today−7, nil below 14
/// values). A nil normal is "Calibrating" — never a fallback band, never `0...0`.
public nonisolated enum KpiNormal {
    public static func make(points: [(date: String, value: Double?)], today: String) -> (normal: PersonalNormalResult?, sevenDay: Double?) {
        var series: [String: Double] = [:]
        for p in points { if let v = p.value, v.isFinite { series[p.date] = v } }
        return ((try? PersonalNormal.normal(series, today: today)) ?? nil,
                (try? PersonalNormal.windowMean(series, today: today)) ?? nil)
    }

    /// "your normal 27–30" once the band exists, else "Calibrating".
    public static func caption(_ n: PersonalNormalResult?, decimals: Int) -> String {
        guard let n else { return JIMissingReason.calibrating.rawValue }
        return "your normal \(jiNumber(n.low, decimals))–\(jiNumber(n.high, decimals))"
    }

    /// A value against its normal: no value = "No data"; no normal yet = "Calibrating".
    public static func status(value: Double?, normal: PersonalNormalResult?) -> JISignalStatus {
        guard let value, value.isFinite else { return .missing(.noData) }
        guard let normal else { return .missing(.calibrating) }
        if value < normal.low { return .belowNormal }
        if value > normal.high { return .aboveNormal }
        return .inNormal
    }
}
