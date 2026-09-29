import Foundation
import Testing
import JICore
import JICompute
@testable import JIFeatures

// W-FIX10 R-01: the periodized week's training / rest days follow the plan's weekdays.

@Test func weeklyPlanTrainingDaysFollowThePlan() {
    // Sunday lifts, Saturday rest.
    var plan = fix10MovedPlan.filter { $0.weekday != 5 && $0.weekday != 6 }
    plan.append(PlanSessionOut(id: 9, name: "Interval Run 2", weekday: 6, sessionType: "cardio"))
    #expect(sessionTypeForWeekDay(.sat, planSessions: plan) == .rest)
    #expect(sessionTypeForWeekDay(.sun, planSessions: plan) == .interval)
    #expect(restWeekDays(planSessions: plan) == [.sat])
    #expect(trainingWeekDays(planSessions: plan).count == 6)
    // No plan → the fixed table, unchanged.
    #expect(sessionTypeForWeekDay(.sun, planSessions: nil) == .rest)
    #expect(restWeekDays(planSessions: []) == restWeekDays)
}

@Test func periodizedPlanUsesThePlanWeek() {
    var plan = fix10MovedPlan.filter { $0.weekday != 5 && $0.weekday != 6 }
    plan.append(PlanSessionOut(id: 9, name: "Interval Run 2", weekday: 6, sessionType: "cardio"))
    let opts = PeriodizedPlanInput(weeklyAvgKcal: 2000, trainKcal: 2100, proteinG: 150, fatG: 60)
    let p = computePeriodizedPlan(opts, planSessions: plan)
    #expect(p.restDays == [.sat])
    #expect(computePeriodizedPlan(opts).restDays == [.sun])
}
