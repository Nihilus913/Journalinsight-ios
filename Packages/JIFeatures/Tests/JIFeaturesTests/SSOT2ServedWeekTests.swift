import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-SSOT-2 S2-3: the Weekly plan (WeeklyPlanMath) and the hero verdict (EffectiveVerdict) read the
// hub's served `/planning/week` — the same answer the gate and Today use — before the plan rows.

/// The served week after a move the rows (`fix10MovedPlan`, Thu = Day 2 strength) do not show yet:
/// Thursday is rest, Sunday holds the strength day, and Wednesday is the hub's retyped "Hill Sprints".
private let servedMovedWeek = PlanWeekOut(start: "2026-09-28", days: [
    PlanWeekDayOut(date: "2026-09-28", weekday: 0, prescription: "Day 1 Full Upper + Z2 40min", type: "strength"),
    PlanWeekDayOut(date: "2026-09-29", weekday: 1, prescription: "Norwegian 4x4 intervals", type: "interval"),
    PlanWeekDayOut(date: "2026-09-30", weekday: 2, prescription: "Hill Sprints", type: "z2"),
    PlanWeekDayOut(date: "2026-10-01", weekday: 3, prescription: "Rest", type: "rest"),
    PlanWeekDayOut(date: "2026-10-02", weekday: 4, prescription: "Day 3 Full Upper + Z2 60min", type: "strength"),
    PlanWeekDayOut(date: "2026-10-03", weekday: 5, prescription: "Norwegian 4x4 intervals", type: "interval"),
    PlanWeekDayOut(date: "2026-10-04", weekday: 6, prescription: "Day 2 Full Upper + Z2 60min", type: "strength"),
])

// MARK: WeeklyPlanMath — week wins over rows

@Test func weeklyPlanMathServedWeekWinsOverRows() {
    // Rows: Thursday = Day 2 (training), Sunday = rest.
    #expect(sessionTypeForWeekDay(.thu, planSessions: fix10MovedPlan) == .strength)
    #expect(sessionTypeForWeekDay(.sun, planSessions: fix10MovedPlan) == .rest)
    // The served week wins: Thursday rest, Sunday strength.
    #expect(sessionTypeForWeekDay(.thu, planSessions: fix10MovedPlan, week: servedMovedWeek) == .rest)
    #expect(sessionTypeForWeekDay(.sun, planSessions: fix10MovedPlan, week: servedMovedWeek) == .strength)
    #expect(trainingWeekDays(planSessions: fix10MovedPlan, week: servedMovedWeek) == [.mon, .tue, .wed, .fri, .sat, .sun])
    #expect(restWeekDays(planSessions: fix10MovedPlan, week: servedMovedWeek) == [.thu])
}

@Test func periodizedPlanBanksOnTheServedRestDay() {
    let input = PeriodizedPlanInput(weeklyAvgKcal: 2000, trainKcal: 2100, proteinG: 150, fatG: 60)
    let plan = computePeriodizedPlan(input, planSessions: fix10MovedPlan, week: servedMovedWeek)
    #expect(plan.restDays == [.thu])
    #expect(plan.days.first { $0.day == .thu }?.high == false)
    #expect(plan.days.first { $0.day == .sun }?.high == true)
    // Without a served week the rows answer exactly as before.
    #expect(computePeriodizedPlan(input, planSessions: fix10MovedPlan).restDays == [.sun])
}

@Test func incompleteServedWeekFallsBackToRows() {
    let partial = PlanWeekOut(start: "2026-09-28", days: Array(servedMovedWeek.days.prefix(4)))
    #expect(sessionTypeForWeekDay(.thu, planSessions: fix10MovedPlan, week: partial) == .strength)
}

@MainActor @Test func weeklyPlanViewModelReadsTheServedWeek() throws {
    let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())),
                                 schedule: { (fix10MovedPlan, servedMovedWeek) })
    #expect(vm.plan.restDays == [.thu])
    let rowsOnly = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())),
                                       schedule: { (fix10MovedPlan, nil) })
    #expect(rowsOnly.plan.restDays == [.sun])
}

// MARK: EffectiveVerdict — week wins over rows

@Test func autoRegulatedPrescriptionServedWeekWinsOverRows() {
    let amber = verdictParts("GO (auto-regulated) — Hill Sprints")
    // The rows still call "Hill Sprints" a strength session …
    let rows = [PlanSessionOut(id: 9, name: "Hill Sprints", weekday: 2, sessionType: "strength")]
    #expect(autoRegulatedPrescription(amber, planSessions: rows) == AutoRegulatedCopy.strength)
    // … the served week retyped it as a Z2 day: the hub's answer wins.
    #expect(autoRegulatedPrescription(amber, planSessions: rows, week: servedMovedWeek) == AutoRegulatedCopy.longZ2)
    // A name only the served week knows is no longer unknown.
    #expect(autoRegulatedPrescription(amber) == nil)
    #expect(autoRegulatedPrescription(amber, week: servedMovedWeek) == AutoRegulatedCopy.longZ2)
}

@Test func decideLinesReadTheServedWeek() {
    let amber = verdictParts("GO (auto-regulated) — Hill Sprints")
    #expect(decidePrescriptionLine(verdict: amber, override: nil) == nil)
    #expect(decidePrescriptionLine(verdict: amber, override: nil, week: servedMovedWeek) == AutoRegulatedCopy.longZ2)
    #expect(decideWhyLine(verdict: amber, override: nil, hasGateSignals: true, heldReason: nil, week: servedMovedWeek)
            == .prescription(AutoRegulatedCopy.longZ2))
    #expect(dayNextCard(verdict: amber, sessionForToday: nil, override: nil, week: servedMovedWeek).prescription
            == AutoRegulatedCopy.longZ2)
}
