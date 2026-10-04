import Foundation

/// W-ONDEVICE O-2 — HRV-guided band on overnight RMSSD. Port of `app/vitals/hrv_band.py` @ cal
/// (W-CAL C-1/C-2), golden-tested bit-for-bit (`hrvband.golden.json`).
///
/// Javaloyes 2019: 7-day rolling ln(RMSSD) vs baseline mean ± 0.5·SD; under → amber. Kiviniemi
/// 2007: two consecutive falling nights under the lower edge → amber. Baseline = the 28 most
/// recent nights before today, Apple and Garmin together (Apple wins a dual-worn night, Garmin
/// RMSSD × `garminRmssdFactor` — the ONE place the device factor lives; the recovery merge reads
/// it). Today's night must be present, else `missing`. Pure; dates are ISO `yyyy-MM-dd`.
public nonisolated enum HrvBandStatus: String, Sendable, Hashable, Codable { case pass, amber, missing }

public nonisolated enum HrvNightSource: String, Sendable, Hashable, Codable { case apple, garmin }

public nonisolated struct HrvBandResult: Hashable, Sendable {
    public let status: HrvBandStatus
    public let nBaseline: Int
    public let rollingLn: Double?
    public let lowerLn: Double?
    public let upperLn: Double?
    public let todayMs: Double?
    public let kiviniemi: Bool
    public let note: String
    /// Fewer than 28 baseline nights: status stays `missing`, this says why.
    public let calibrating: Bool
    public let nApple: Int
    public let nGarmin: Int

    public init(status: HrvBandStatus, nBaseline: Int, rollingLn: Double?, lowerLn: Double?, upperLn: Double?,
                todayMs: Double?, kiviniemi: Bool, note: String, calibrating: Bool = false, nApple: Int = 0, nGarmin: Int = 0) {
        self.status = status; self.nBaseline = nBaseline; self.rollingLn = rollingLn; self.lowerLn = lowerLn
        self.upperLn = upperLn; self.todayMs = todayMs; self.kiviniemi = kiviniemi; self.note = note
        self.calibrating = calibrating; self.nApple = nApple; self.nGarmin = nGarmin
    }
}

public nonisolated enum HrvBand {
    public static let baselineNights = 28
    public static let rollingNights = 7
    public static let swcFactor = 0.5
    /// W-CAL C-1: Garmin nightly RMSSD × this = the Watch-equivalent value (default −5 %).
    public static let garminRmssdFactor = 0.95
    /// Dual-worn nights needed before the factor is fitted from data.
    public static let minDualNights = 7

    private static func pos(_ v: Double?) -> Bool { (v ?? 0) > 0 }

    /// Median Apple/Garmin ratio over dual-worn nights; the default below `minDualNights`.
    public static func fitDeviceFactor(apple: [String: Double], garmin: [String: Double]) -> Double {
        var ratios: [Double] = []
        for (d, a) in apple where pos(a) && pos(garmin[d]) { ratios.append(a / garmin[d]!) }
        return ratios.count < minDualNights ? garminRmssdFactor : Baseline.median(ratios)
    }

    /// One nightly series: Apple as is, Garmin × factor on nights without a positive Apple value.
    public static func combineNightly(apple: [String: Double], garmin: [String: Double]?,
                                      factor: Double? = nil) -> (values: [String: Double], source: [String: HrvNightSource]) {
        let garmin = garmin ?? [:]
        let f = factor ?? fitDeviceFactor(apple: apple, garmin: garmin)
        var merged: [String: Double] = [:]
        var src: [String: HrvNightSource] = [:]
        for (d, v) in garmin where pos(v) { merged[d] = v * f; src[d] = .garmin }
        for (d, v) in apple where pos(v) { merged[d] = v; src[d] = .apple }
        return (merged, src)
    }

    public static func calibratingNote(nApple: Int, nGarmin: Int) -> String {
        "HRV baseline calibrating — \(nApple) Apple + \(nGarmin) Garmin nights (\(nApple + nGarmin)/\(baselineNights))"
    }

    /// Python `round(x)` for a float (half-even) as an Int.
    private static func pyRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }
    private static func ms(_ ln: Double) -> Int { pyRound(Foundation.exp(ln)) }

    /// `apple` = Apple overnight RMSSD; `garmin` (optional, empty = none) = Garmin nightly RMSSD,
    /// scaled and used only on nights without an Apple value.
    public static func compute(apple: [String: Double], today: String, garmin: [String: Double]? = nil,
                               factor: Double? = nil) throws -> HrvBandResult {
        let nightly: [String: Double]
        let src: [String: HrvNightSource]
        if let garmin, !garmin.isEmpty {
            (nightly, src) = combineNightly(apple: apple, garmin: garmin, factor: factor)
        } else {
            nightly = apple
            src = apple.mapValues { _ in .apple }
        }
        let prior = nightly.keys.filter { $0 < today && pos(nightly[$0]) }.sorted(by: >)
        let base = Array(prior.prefix(baselineNights))
        let nG = base.filter { src[$0] == .garmin }.count
        let nA = base.count - nG
        let todayMs = nightly[today]
        if base.count < baselineNights {
            return HrvBandResult(status: .missing, nBaseline: base.count, rollingLn: nil, lowerLn: nil, upperLn: nil,
                                 todayMs: todayMs, kiviniemi: false, note: calibratingNote(nApple: nA, nGarmin: nG),
                                 calibrating: true, nApple: nA, nGarmin: nG)
        }
        guard let t = todayMs, t > 0 else {
            return HrvBandResult(status: .missing, nBaseline: base.count, rollingLn: nil, lowerLn: nil, upperLn: nil,
                                 todayMs: nil, kiviniemi: false, note: "waiting for last night", nApple: nA, nGarmin: nG)
        }
        let ln = base.map { Foundation.log(nightly[$0]!) }
        let mean = PythonStatistics.mean(ln)
        let sd = PythonStatistics.stdev(ln)
        let lower = mean - swcFactor * sd
        let upper = mean + swcFactor * sd
        var windowLn: [Double] = []
        for k in 0..<rollingNights {
            if let v = nightly[try CalendarMath.addDays(today, -k)], v > 0 { windowLn.append(Foundation.log(v)) }
        }
        let rolling = PythonStatistics.mean(windowLn)
        let y = nightly[try CalendarMath.addDays(today, -1)]
        let tLn = Foundation.log(t)
        var kiv = false
        if let y, y > 0 {
            let yLn = Foundation.log(y)
            kiv = yLn < lower && tLn < lower && tLn < yLn
        }
        if kiv {
            return HrvBandResult(status: .amber, nBaseline: base.count, rollingLn: rolling, lowerLn: lower, upperLn: upper,
                                 todayMs: t, kiviniemi: true,
                                 note: "HRV \(pyRound(t)) ms — 2 nights falling below \(ms(lower)) ms", nApple: nA, nGarmin: nG)
        }
        if rolling < lower {
            return HrvBandResult(status: .amber, nBaseline: base.count, rollingLn: rolling, lowerLn: lower, upperLn: upper,
                                 todayMs: t, kiviniemi: false,
                                 note: "HRV 7-day \(ms(rolling)) ms — under band \(ms(lower))–\(ms(upper)) ms", nApple: nA, nGarmin: nG)
        }
        return HrvBandResult(status: .pass, nBaseline: base.count, rollingLn: rolling, lowerLn: lower, upperLn: upper,
                             todayMs: t, kiviniemi: false,
                             note: "HRV 7-day \(ms(rolling)) ms — inside/above band \(ms(lower))–\(ms(upper)) ms", nApple: nA, nGarmin: nG)
    }
}
