/// W-FIX2 L5 (FM-08 app side): `GET /api/v1/vitals/sleep-summary` — last night's Apple-era sleep
/// as the hub serves it: the computed 0–100 score (`core.daily_sleep.sleep_score_computed`, the
/// value Today's Sleep ring shows), the stages, and the sleep debt. Every field is optional on the
/// wire: a night the hub has nothing for decodes to nil ("—"), never a zero (rule 5).
public struct SleepSummary: Codable, Sendable, Equatable {
    public var scoreComputed: Double?
    public var scoreComputedDate: String?
    public var debtHours: Double?

    public init(scoreComputed: Double? = nil, scoreComputedDate: String? = nil, debtHours: Double? = nil) {
        self.scoreComputed = scoreComputed; self.scoreComputedDate = scoreComputedDate; self.debtHours = debtHours
    }
}

/// The screen-side seam for `/vitals/sleep-summary` (same convention as `WeighInProviding`: the
/// frozen `HealthDataProvider` is not widened; a provider that can serve it conforms). A provider
/// that does not (T2, previews) simply isn't cast to it, and the Sleep ring keeps its fallback.
public protocol SleepSummaryProviding: Sendable {
    /// `GET /api/v1/vitals/sleep-summary`
    func sleepSummary() async throws -> SleepSummary
}
