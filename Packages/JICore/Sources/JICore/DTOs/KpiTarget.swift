/// W3b-L2 (P-kpi) — `GET/PUT /api/v1/planning/kpi-targets` wire contracts. Field names mirror
/// `app/planning/router.py::KpiTargetOut`/`KpiTargetUpdate` exactly (plan.kpi_target rows: a gate
/// rule per (metric, operator) pair — NOT one-per-KpiMetricId; several rules can share a metric,
/// e.g. three separate `acwr` rows in the seeded fixture). `metric`/`operator` are immutable
/// through the PUT; only `threshold`/`thresholdHi`/`description` are ever sent back.
public struct KpiTarget: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { targetId }
    public var targetId: Int
    public var metric: String
    public var `operator`: String
    public var threshold: Double
    public var thresholdHi: Double?
    public var description: String?

    public init(targetId: Int, metric: String, operator op: String, threshold: Double, thresholdHi: Double? = nil, description: String? = nil) {
        self.targetId = targetId; self.metric = metric; self.operator = op
        self.threshold = threshold; self.thresholdHi = thresholdHi; self.description = description
    }
}

/// `GET /api/v1/planning/kpi-targets` envelope (`KpiTargetsResponse`).
public struct KpiTargetsResponse: Codable, Sendable, Equatable {
    public var targets: [KpiTarget]
    public init(targets: [KpiTarget]) { self.targets = targets }
}

/// `PUT /api/v1/planning/kpi-targets/{id}` body (`KpiTargetUpdate`, `extra="forbid"` server-side —
/// send exactly these three fields, nothing else). `HubClient.send` encodes with a plain
/// `JSONEncoder()` (no `.convertToSnakeCase`, see its doc comment), so this type snake-cases its
/// own wire keys explicitly, same convention as `ExerciseUpdate` (W3a).
public struct KpiTargetUpdateBody: Encodable, Sendable {
    public var threshold: Double
    public var thresholdHi: Double?
    public var description: String?

    public init(threshold: Double, thresholdHi: Double? = nil, description: String? = nil) {
        self.threshold = threshold; self.thresholdHi = thresholdHi; self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case threshold
        case thresholdHi = "threshold_hi"
        case description
    }
}
