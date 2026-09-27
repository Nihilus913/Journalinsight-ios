import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

@Test @MainActor func goalsViewModelAddSetProgressDeleteRoundTrip() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    #expect(vm.goals.isEmpty)

    vm.addGoal(title: "Bench 100kg", targetDate: "2026-12-31")
    #expect(vm.goals.count == 1)
    let id = vm.goals[0].id

    vm.setProgress(id: id, progress: 0.4)
    #expect(vm.goals[0].progress == 0.4)

    vm.deleteGoal(id: id)
    #expect(vm.goals.isEmpty)
}

@Test @MainActor func goalsViewModelAddGoalIgnoresBlankTitle() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    vm.addGoal(title: "   ", targetDate: nil)
    #expect(vm.goals.isEmpty)
}

@Test @MainActor func goalsViewModelSetProgressClamps() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    vm.addGoal(title: "g", targetDate: nil)
    let id = vm.goals[0].id
    vm.setProgress(id: id, progress: 1.7)
    #expect(vm.goals[0].progress == 1)
}

// B-57 W5 B4: the Goals "Training plan" row counts this week from the cached plan; no week = "—".
private func kcalRow(_ date: String, _ v: Double) -> DailyKpiRow {
    var r = try! JSON.decoder.decode(DailyKpiRow.self, from: Data("{\"date\":\"\(date)\"}".utf8))
    r.values = ["kcal_burned_active": v]
    return r
}

@Test func trainingPlanRowCountsTheWeek() {
    let plan = [PlanSessionOut(id: 1, name: "D1", weekday: 0), PlanSessionOut(id: 2, name: "D2", weekday: 2)]
    let wk = trainingWeekSummary(planSessions: plan, exercises: [], daily: [kcalRow("2026-09-21", 400)], today: "2026-09-23")
    #expect(goalsTrainingPlanValue(wk) == ("1 of 2", "On plan"))
    #expect(goalsTrainingPlanValue(nil) == ("—", "No data"))
    let open = trainingWeekSummary(planSessions: plan + [PlanSessionOut(id: 3, name: "D3", weekday: nil)], exercises: [], daily: [], today: "2026-09-23")
    #expect(goalsTrainingPlanValue(open) == ("— of 3", "1 to assign"))
    let done = trainingWeekSummary(planSessions: plan, exercises: [], daily: [kcalRow("2026-09-21", 400), kcalRow("2026-09-23", 500)], today: "2026-09-23")
    #expect(goalsTrainingPlanValue(done) == ("2 of 2", "Done"))
}

@Test func trainingPlanTargetRowReadsTheWeekNotAFixedFour() {
    let plan = [PlanSessionOut(id: 1, name: "D1", weekday: 0), PlanSessionOut(id: 2, name: "D2", weekday: 2),
                PlanSessionOut(id: 3, name: "D3", weekday: 4)]
    let wk = trainingWeekSummary(planSessions: plan, exercises: [], daily: [kcalRow("2026-09-21", 400)], today: "2026-09-23")
    let row = GoalsBoard.targets(goals: nil, macros: nil, yesterdayKcal: nil, yesterdayProteinG: nil, yesterdaySteps: nil, week: wk)
        .first { $0.title == goalsTrainingPlanTitle }
    #expect(row?.value == "1 of 3" && row?.status == "On plan")
    let none = GoalsBoard.targets(goals: nil, macros: nil, yesterdayKcal: nil, yesterdayProteinG: nil, yesterdaySteps: nil)
        .first { $0.title == goalsTrainingPlanTitle }
    #expect(none?.value == "— No data" && none?.status == nil)
}
