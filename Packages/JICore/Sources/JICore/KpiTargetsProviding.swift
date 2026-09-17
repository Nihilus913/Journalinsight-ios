import Foundation

/// W3b-L2 (P-kpi) — this screen's own hub slice, added fresh rather than growing the frozen
/// `HealthDataProvider` (same rationale as `EnergyProviding`/`NutritionProviding`/
/// `TrainingProviding`, W3a): each screen lane owns its own protocol so parallel lanes never
/// collide on one shared interface.
public protocol KpiTargetsProviding: Sendable {
    /// `GET /api/v1/planning/kpi-targets`
    func kpiTargets() async throws -> [KpiTarget]

    /// `PUT /api/v1/planning/kpi-targets/{id}` — updates threshold/thresholdHi/description on one
    /// rule; `metric`/`operator` stay server-immutable. Returns the server's full updated row.
    func updateKpiTarget(id: Int, threshold: Double, thresholdHi: Double?, description: String?) async throws -> KpiTarget
}
