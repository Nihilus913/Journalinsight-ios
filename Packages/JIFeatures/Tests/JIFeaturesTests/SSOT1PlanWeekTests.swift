import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-SSOT-1 SS-7: when the hub serves `/planning/week`, the app's day → session answer IS the hub's
// `session_for`; the plan-session rows are only the fallback (older hub / route missing).

/// The hub's week after a move the rows do not show yet: Wednesday holds intervals.
private let servedWeek = PlanWeekOut(start: "2026-09-28", days: [
    PlanWeekDayOut(date: "2026-09-28", weekday: 0, prescription: "Day 1 Full Upper + Z2 40min", type: "strength"),
    PlanWeekDayOut(date: "2026-09-29", weekday: 1, prescription: "Long Zone 2 75-90min", type: "z2"),
    PlanWeekDayOut(date: "2026-09-30", weekday: 2, prescription: "Norwegian 4x4 intervals", type: "interval"),
    PlanWeekDayOut(date: "2026-10-01", weekday: 3, prescription: "Day 2 Full Upper + Z2 60min", type: "strength"),
    PlanWeekDayOut(date: "2026-10-02", weekday: 4, prescription: "Day 3 Full Upper + Z2 60min", type: "strength"),
    PlanWeekDayOut(date: "2026-10-03", weekday: 5, prescription: "Norwegian 4x4 intervals", type: "interval"),
    PlanWeekDayOut(date: "2026-10-04", weekday: 6, prescription: "Rest", type: "rest"),
])

private nonisolated struct WeekServingProvider: HealthDataProvider, TrainingProviding {
    let capabilities: DataCapability = .hubAll
    let rows = Fix10TodayProvider(plan: fix10MovedPlan, reason: nil)
    let week: PlanWeekOut?
    func health() async throws -> HealthResponse { try await rows.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await rows.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await rows.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await rows.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await rows.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await rows.syncStatus() }
    func trainingDay(date: String) async throws -> TrainingDayDetail { try await rows.trainingDay(date: date) }
    func exercises() async throws -> [Exercise] { try await rows.exercises() }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        try await rows.updateExercise(exerciseId: exerciseId, patch: patch)
    }
    func planSessions() async throws -> [PlanSessionOut] { try await rows.planSessions() }
    func planWeek(start: String) async throws -> PlanWeekOut {
        guard let week, week.start == start else { throw PlanWeekUnavailable() }
        return week
    }
}

private let wednesday = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!

@Test func planWeekStartIsTheMonday() {
    #expect(planWeekStart("2026-09-30") == "2026-09-28")
    #expect(planWeekStart("2026-09-28") == "2026-09-28")
    #expect(planWeekStart("2026-10-04") == "2026-09-28")
    #expect(planWeekStart("not a date") == nil)
}

@Test func scheduledSessionPrefersTheServedWeek() {
    // Rows say Wednesday = long Z2; the served week says intervals — the hub wins.
    #expect(scheduledSession(on: "2026-09-30", planSessions: fix10MovedPlan, week: servedWeek)?.name == "Norwegian 4x4 intervals")
    #expect(scheduledSession(on: "2026-09-30", planSessions: fix10MovedPlan, week: servedWeek)?.type == .interval)
    // Without a week the rows answer exactly as before.
    #expect(scheduledSession(on: "2026-09-30", planSessions: fix10MovedPlan, week: nil)?.name == "Long Zone 2 75-90min")
    // A later date outside the served week takes the served week's weekday (the plan the hub
    // read), not the rows'; history before the changeover keeps the fixed table.
    #expect(scheduledSession(on: "2026-10-07", planSessions: fix10MovedPlan, week: servedWeek)?.name == "Norwegian 4x4 intervals")
    #expect(scheduledSession(on: "2026-09-23", planSessions: fix10MovedPlan, week: servedWeek)?.name == "Day 2 Full Upper + Z2 60min")
}

@Test @MainActor func todayReadsTheServedWeekFirst() async throws {
    let vm = TodayViewModel(provider: WeekServingProvider(week: servedWeek),
                            cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await vm.load()
    #expect(vm.scheduledSessionToday == "Norwegian 4x4 intervals")
}

@Test @MainActor func todayFallsBackToPlanRowsWhenTheWeekIsNotServed() async throws {
    let vm = TodayViewModel(provider: WeekServingProvider(week: nil),
                            cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await vm.load()
    #expect(vm.scheduledSessionToday == "Long Zone 2 75-90min")
}
