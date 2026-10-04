import Testing
@testable import JICompute

/// B-110: the KPI gate must not fire "REDUCE: overreaching" while the user is on a break.
/// Parity with the hub's `evaluate_kpi_gates(paused=)` (HT tests/test_b110_gate_paused.py):
/// while Paused every `acwr` rule is skipped; nutrition + sleep rules still fire.
struct KpiGatePausedTests {
    private func week(acwr: Double, kcal: Double = 2100) -> [KpiMetricRow] {
        (0..<7).map { _ in
            ["kcal_consumed": kcal, "protein_g": 170, "sleep_score": 75, "acwr": acwr,
             "weight_kg": 82, "kcal_goal": 2100, "meals_logged": 4]
        }
    }

    @Test func overreachingFiresWhenNotPaused() {
        let r = evaluateKpiGates(week(acwr: 1.6), defaultKpiRules)
        #expect(r.recommendation == .reduce)
        #expect(r.triggeredRules.first?.contains("overreaching") == true)
    }

    @Test func overreachingSuppressedWhilePaused() {
        let r = evaluateKpiGates(week(acwr: 1.6), defaultKpiRules, paused: true)
        #expect(r.recommendation == .maintain)
        #expect(!r.triggeredRules.contains { $0.contains("overreaching") })
    }

    @Test func undertrainingSuppressedWhilePaused() {
        let r = evaluateKpiGates(week(acwr: 0.3), defaultKpiRules, paused: true)
        #expect(r.recommendation == .maintain && r.triggeredRules.isEmpty)
    }

    @Test func nutritionRuleStillFiresWhilePaused() {
        let r = evaluateKpiGates(week(acwr: 1.6, kcal: 1300), defaultKpiRules, paused: true)
        #expect(r.recommendation == .reduce)
        #expect(r.triggeredRules.first?.contains("underfueling") == true)
    }

    @Test func evaluateGatePassesPausedThrough() {
        #expect(evaluateGate(week(acwr: 1.6), defaultKpiRules).recommendation == .reduce)
        #expect(evaluateGate(week(acwr: 1.6), defaultKpiRules, paused: true).recommendation == .maintain)
    }
}
