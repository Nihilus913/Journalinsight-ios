/// W-FIX2 L5 (FM-08 app side): `GET /api/v1/vitals/sleep-summary` — last night's Apple-era sleep
/// as the hub serves it: the computed 0–100 score (`core.daily_sleep.sleep_score_computed`, the
/// value Today's Sleep ring shows), the stages, and the sleep debt. Every field is optional on the
/// wire: a night the hub has nothing for decodes to nil ("—"), never a zero (rule 5).
public struct SleepSummary: Codable, Sendable, Equatable {
    public var scoreComputed: Double?
    public var scoreComputedDate: String?
    public var scoreComputedSource: String?
    public var debtHours: Double?
    public var debtBaselineHours: Double?
    public var debtDate: String?
    public var debtSource: String?
    public var bedtimeConsistencySdMin: Double?
    public var bedtimeConsistencyNights: Int?
    public var bedtimeConsistencySources: [String]?
    public var lastNightDate: String?
    public var lastNightDurationSec: Double?
    public var lastNightDeepSleepSec: Double?
    public var lastNightLightSleepSec: Double?
    public var lastNightRemSleepSec: Double?
    public var lastNightSource: String?

    public init(
        scoreComputed: Double? = nil, scoreComputedDate: String? = nil, scoreComputedSource: String? = nil,
        debtHours: Double? = nil, debtBaselineHours: Double? = nil, debtDate: String? = nil, debtSource: String? = nil,
        bedtimeConsistencySdMin: Double? = nil, bedtimeConsistencyNights: Int? = nil, bedtimeConsistencySources: [String]? = nil,
        lastNightDate: String? = nil, lastNightDurationSec: Double? = nil, lastNightDeepSleepSec: Double? = nil,
        lastNightLightSleepSec: Double? = nil, lastNightRemSleepSec: Double? = nil, lastNightSource: String? = nil
    ) {
        self.scoreComputed = scoreComputed; self.scoreComputedDate = scoreComputedDate; self.scoreComputedSource = scoreComputedSource
        self.debtHours = debtHours; self.debtBaselineHours = debtBaselineHours; self.debtDate = debtDate; self.debtSource = debtSource
        self.bedtimeConsistencySdMin = bedtimeConsistencySdMin; self.bedtimeConsistencyNights = bedtimeConsistencyNights
        self.bedtimeConsistencySources = bedtimeConsistencySources
        self.lastNightDate = lastNightDate; self.lastNightDurationSec = lastNightDurationSec
        self.lastNightDeepSleepSec = lastNightDeepSleepSec; self.lastNightLightSleepSec = lastNightLightSleepSec
        self.lastNightRemSleepSec = lastNightRemSleepSec; self.lastNightSource = lastNightSource
    }
}

/// The screen-side seam for `/vitals/sleep-summary` (same convention as `WeighInProviding`: the
/// frozen `HealthDataProvider` is not widened; a provider that can serve it conforms). A provider
/// that does not (T2, previews) simply isn't cast to it, and the Sleep ring keeps its fallback.
public protocol SleepSummaryProviding: Sendable {
    /// `GET /api/v1/vitals/sleep-summary`
    func sleepSummary() async throws -> SleepSummary
}
