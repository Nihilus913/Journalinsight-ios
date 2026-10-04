/// W-FIX2 L5 (FM-08 app side): `GET /api/v1/vitals/sleep-summary` — last night's Apple-era sleep
/// as the hub serves it: the computed 0–100 score (`core.daily_sleep.sleep_score_computed`, the
/// value Today's Sleep ring shows), the stages, and the sleep debt. Every field is optional on the
/// wire: a night the hub has nothing for decodes to nil ("—"), never a zero (rule 5).
public struct SleepSummary: Codable, Sendable, Equatable {
    public var scoreComputed: Double?
    public var scoreComputedDate: String?
    public var debtHours: Double?
    /// W-B67 R-2: the source of `scoreComputed` ("AppleHealth" / "GarminAPI"); nil on old hubs.
    public var scoreComputedSource: String?
    /// W-B67 R-2: how `scoreComputed` is built (hub `compute_sleep_score_breakdown`, same row).
    /// nil on hubs older than W-B67 — the KPI detail then hides its breakdown section.
    public var scoreBreakdown: SleepScoreBreakdown?
    /// W-B67 R-2: last night's time awake after sleep onset (s); nil = not reported.
    public var lastNightAwakeSec: Int?

    public init(scoreComputed: Double? = nil, scoreComputedDate: String? = nil, debtHours: Double? = nil,
                scoreComputedSource: String? = nil, scoreBreakdown: SleepScoreBreakdown? = nil,
                lastNightAwakeSec: Int? = nil) {
        self.scoreComputed = scoreComputed; self.scoreComputedDate = scoreComputedDate; self.debtHours = debtHours
        self.scoreComputedSource = scoreComputedSource; self.scoreBreakdown = scoreBreakdown
        self.lastNightAwakeSec = lastNightAwakeSec
    }
}

/// W-B67 R-2: one component of the computed sleep score as the hub serves it
/// (`key` duration | deep | rem | continuity; `points` 1 dp of `max`; `value` seconds;
/// `share` of sleep time; `target` share; `inferred` = stage missing, credited 80 %).
public struct SleepScoreComponent: Codable, Sendable, Equatable {
    public var key: String
    public var points: Double
    public var max: Int
    public var value: Int?
    public var share: Double?
    public var target: Double?
    public var inferred: Bool

    public init(key: String, points: Double, max: Int, value: Int? = nil, share: Double? = nil,
                target: Double? = nil, inferred: Bool = false) {
        self.key = key; self.points = points; self.max = max; self.value = value
        self.share = share; self.target = target; self.inferred = inferred
    }
}

/// W-B67 R-2: `score_breakdown` — `total` equals `score_computed`.
public struct SleepScoreBreakdown: Codable, Sendable, Equatable {
    public var total: Int
    public var components: [SleepScoreComponent]

    public init(total: Int, components: [SleepScoreComponent]) {
        self.total = total; self.components = components
    }
}

/// The screen-side seam for `/vitals/sleep-summary` (same convention as `WeighInProviding`: the
/// frozen `HealthDataProvider` is not widened; a provider that can serve it conforms). A provider
/// that does not (T2, previews) simply isn't cast to it, and the Sleep ring keeps its fallback.
public protocol SleepSummaryProviding: Sendable {
    /// `GET /api/v1/vitals/sleep-summary`
    func sleepSummary() async throws -> SleepSummary
}
