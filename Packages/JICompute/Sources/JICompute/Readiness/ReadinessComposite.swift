/// W-ONDEVICE O-5 (B-19) — the self-owned categorical readiness composite. Port of
/// `app/vitals/readiness_composite.py` (`compute_readiness_category`, `load7_session` and the
/// series assembly of `categorical_readiness_from_db`) on the O-1 `Baseline` primitive.
/// Ranking-grade only: ordinal parity (category per day) is the contract, NEVER gate-wired,
/// never shown as a Garmin-equivalent digit. Weights and thresholds are hand-set CONVENTION
/// (see the Python docstring), mirrored here as constants and checked against the golden.
public nonisolated enum ReadinessCategory: String, Sendable, Hashable, Codable { case low, moderate, high }

public nonisolated struct ReadinessCategoryResult: Hashable, Sendable {
    /// nil when HRV or RHR has no warmed-up baseline (fails closed).
    public let category: ReadinessCategory?
    /// The weighted sum, for debugging/calibration only.
    public let composite: Double?
    public let hrvZ: Double?
    public let rhrZ: Double?
    public let sleepScore: Int?
    public let loadZ: Double?

    public init(category: ReadinessCategory?, composite: Double?, hrvZ: Double?, rhrZ: Double?,
                sleepScore: Int?, loadZ: Double?) {
        self.category = category; self.composite = composite; self.hrvZ = hrvZ; self.rhrZ = rhrZ
        self.sleepScore = sleepScore; self.loadZ = loadZ
    }
}

public nonisolated enum ReadinessComposite {
    /// The `ParityRegistry` key this type implements.
    public static let registryKey = "readiness_categorical"

    public static let wHrv = 0.35
    public static let wRhr = 0.35
    public static let wSleep = 0.20
    public static let wLoad = 0.10
    public static let sleepCenter = 65.0
    public static let sleepSpread = 20.0
    public static let highThreshold = 0.40
    public static let lowThreshold = -0.40
    /// load7Session needs this many known days of 7.
    public static let load7MinDays = 4

    /// HRV and RHR z required; sleep score and load z degrade to a neutral 0 when absent.
    public static func computeReadinessCategory(hrvZ: Double?, rhrZ: Double?, sleepScore: Int?,
                                                loadZ: Double?) -> ReadinessCategoryResult {
        guard let h = hrvZ, let r = rhrZ else {
            return ReadinessCategoryResult(category: nil, composite: nil, hrvZ: hrvZ, rhrZ: rhrZ,
                                           sleepScore: sleepScore, loadZ: loadZ)
        }
        let sleepComponent = sleepScore.map { (Double($0) - sleepCenter) / sleepSpread } ?? 0.0
        let loadComponent = loadZ ?? 0.0
        // Same left-to-right evaluation order as the Python expression (bit-exact).
        let composite = wHrv * h - wRhr * r + wSleep * sleepComponent - wLoad * loadComponent
        let category: ReadinessCategory
        if composite >= highThreshold { category = .high }
        else if composite <= lowThreshold { category = .low }
        else { category = .moderate }
        return ReadinessCategoryResult(category: category, composite: composite, hrvZ: hrvZ, rhrZ: rhrZ,
                                       sleepScore: sleepScore, loadZ: loadZ)
    }

    /// Trailing 7-day sum of daily session load ending on (and including) `target`; a present
    /// date is known (0 = a real rest day). nil with fewer than 4 known days.
    public static func load7Session(target: String, dailyLoad: [String: Double]) throws -> Double? {
        var total = 0.0
        var n = 0
        for k in 0..<7 {
            if let v = dailyLoad[try CalendarMath.addDays(target, -k)] { total += v; n += 1 }
        }
        return n >= load7MinDays ? total : nil
    }

    /// `categorical_readiness_from_db` without the SQL: HRV, RHR, sleep score and daily session
    /// load series in, the category for `target` out (load7Session over target−120…target, then
    /// each z via `Baseline.trailingZ`).
    public static func categorical(target: String, hrv: [String: Double], rhr: [String: Double],
                                   sleepScore: [String: Int], dailyLoad: [String: Double]) throws -> ReadinessCategoryResult {
        var loadSeries: [String: Double] = [:]
        for offset in 0...Baseline.windowDays {
            let d = try CalendarMath.addDays(target, -offset)
            if let v = try load7Session(target: d, dailyLoad: dailyLoad) { loadSeries[d] = v }
        }
        return computeReadinessCategory(hrvZ: try Baseline.trailingZ(target: target, series: hrv),
                                        rhrZ: try Baseline.trailingZ(target: target, series: rhr),
                                        sleepScore: sleepScore[target],
                                        loadZ: try Baseline.trailingZ(target: target, series: loadSeries))
    }
}
