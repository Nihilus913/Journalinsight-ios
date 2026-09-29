import Foundation

/// W3b-L2 (P-kpi) — this screen's own hub slice, added fresh rather than growing the frozen
/// `HealthDataProvider` (same rationale as `EnergyProviding`/`NutritionProviding`/
/// `TrainingProviding`, W3a): each screen lane owns its own protocol so parallel lanes never
/// collide on one shared interface.
public protocol KpiTargetsProviding: Sendable {
    /// `GET /api/v1/planning/kpi-targets`
    func kpiTargets() async throws -> [KpiTarget]
    // W-FIX10 F10-1: `updateKpiTarget` (`PUT /kpi-targets/{id}`, removed hub-side by W-TGT, no
    // caller) is gone — a rule threshold is a Rule in the targets document now.
}
