import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-FIX10 part 2, lane xc-today — R-01 (the day's session follows plan.plan_session.weekday, one
// resolver), R-02 (Today's workout rows by start time), R-05 (the held "Waiting for the watch" reason).

/// The hub's plan with Wednesday and Thursday swapped in the day sheet.
let fix10MovedPlan: [PlanSessionOut] = [
    PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
    PlanSessionOut(id: 2, name: "Interval Run", weekday: 1, sessionType: "cardio"),
    PlanSessionOut(id: 3, name: "Day 2 Full Upper", weekday: 3, sessionType: "strength"),
    PlanSessionOut(id: 4, name: "Long Zone 2", weekday: 2, sessionType: "cardio"),
    PlanSessionOut(id: 5, name: "Day 3 Full Upper", weekday: 4, sessionType: "strength"),
    PlanSessionOut(id: 6, name: "Interval Run 2", weekday: 5, sessionType: "cardio"),
    PlanSessionOut(id: 7, name: "Rest", weekday: 6, sessionType: "rest"),
]

let fix10HeldReason = "Waiting for the watch — last night has not synced yet; this updates when it lands."

/// Mock hub + a plan and a morning-verdict row of our choosing.
nonisolated struct Fix10TodayProvider: HealthDataProvider, TrainingProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let plan: [PlanSessionOut]?
    let reason: String?
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict {
        var v = try await inner.morningVerdict(date: date)
        v.date = date; v.reason = reason
        return v
    }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
    func trainingDay(date: String) async throws -> TrainingDayDetail { try await inner.trainingDay(date: date) }
    func exercises() async throws -> [Exercise] { try await inner.exercises() }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        try await inner.updateExercise(exerciseId: exerciseId, patch: patch)
    }
    func planSessions() async throws -> [PlanSessionOut] {
        guard let plan else { throw PlanSessionListUnavailable() }
        return plan
    }
}

/// 2026-09-30 is a Wednesday.
private let wednesday = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!

// MARK: R-01

@Test func scheduledSessionFollowsTheMovedPlan() {
    #expect(scheduledSession(on: "2026-09-30", planSessions: fix10MovedPlan)?.name == "Long Zone 2 75-90min")
    #expect(scheduledSession(on: "2026-10-01", planSessions: fix10MovedPlan)?.name == "Day 2 Full Upper + Z2 60min")
    // No plan read → the fixed table (fallback).
    #expect(scheduledSession(on: "2026-09-30", planSessions: [])?.name == "Day 2 Full Upper + Z2 60min")
    // History before the changeover keeps the table.
    #expect(scheduledSession(on: "2026-09-23", planSessions: fix10MovedPlan)?.name == "Day 2 Full Upper + Z2 60min")
}

@Test func trainingWeekFallbackFollowsThePlan() {
    // Only strength sessions in `otherSessions` → the cardio days come from the resolver, not the table.
    let strengthOnly = fix10MovedPlan.filter { $0.sessionType == "strength" }
    let moved = fix10MovedPlan
    let week = trainingWeekSummary(planSessions: strengthOnly, exercises: [], daily: [], today: "2026-09-30",
                                   otherSessions: [])
    // Without the cardio rows the fixed table answers: Wednesday is a table strength day with no
    // strength session on it any more, so it reads rest — the moved long run is lost.
    #expect(week.days[2].kind == .rest)
    let viaPlan = trainingWeekSummary(planSessions: strengthOnly, exercises: [], daily: [], today: "2026-09-30",
                                      otherSessions: [], schedule: moved)
    #expect(viaPlan.days[2].kind == .longRun)
    #expect(viaPlan.days[3].kind == .strength)
}

@Test func autoRegulatedPrescriptionReadsTheSessionKindFromThePlan() {
    let amber = verdictParts("GO (auto-regulated) — Day 4 Full Upper")
    // A strength session the fixed table never had: the plan knows it.
    let plan = fix10MovedPlan + [PlanSessionOut(id: 8, name: "Day 4 Full Upper", weekday: 6, sessionType: "strength")]
    #expect(autoRegulatedPrescription(amber) == nil)
    #expect(autoRegulatedPrescription(amber, planSessions: plan) == AutoRegulatedCopy.strength)
}

@Test @MainActor func todayPlannedLabelComesFromThePlanWhenTheHubSaysNothing() async throws {
    let vm = TodayViewModel(provider: Fix10TodayProvider(plan: fix10MovedPlan, reason: nil),
                            cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await vm.load()
    // The fixture's `session_for_today` is null and its verdict is Tuesday's intervals.
    #expect(vm.scheduledSessionToday == "Long Zone 2 75-90min")
    #expect(vm.plannedSessionLabel == "Long Zone 2 75-90min")
}

@Test @MainActor func todayWithoutAPlanKeepsTheHubsLabels() async throws {
    let vm = TodayViewModel(provider: Fix10TodayProvider(plan: nil, reason: nil),
                            cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await vm.load()
    #expect(vm.scheduledSessionToday == nil)
    #expect(vm.plannedSessionLabel == "Norwegian 4x4 intervals")
}

@Test func dayNextCardUsesTheScheduledSessionWhenTheHubSentNone() {
    let verdict = verdictParts("GO")
    let card = dayNextCard(verdict: verdict, sessionForToday: dayNextSessionForToday(hub: nil, scheduled: "Long Zone 2 75-90min"),
                           override: nil)
    #expect(card.session == "Long Zone 2 75-90min")
    #expect(dayNextSessionForToday(hub: "Day 1 Full Upper", scheduled: "Rest") == "Day 1 Full Upper")
    #expect(dayNextSessionForToday(hub: " ", scheduled: "Rest") == "Rest")
}

// MARK: R-02

@Test func todayHubWorkoutsAreOrderedByStartTime() {
    let late = DayActivity(activityId: 1, type: "running", name: "Evening run", durationSec: 1800, distanceM: nil,
                           startTimeUtc: "2026-09-30T17:00:00+00:00")
    let early = DayActivity(activityId: 9, type: "strength_training", name: "Lifts", durationSec: 3000, distanceM: nil,
                            startTimeUtc: "2026-09-30T06:00:00+00:00")
    let unknown = DayActivity(activityId: 2, type: "walking", name: "Walk", durationSec: 600, distanceM: nil)
    #expect(dayNextHubWorkouts([late, unknown, early], done: .none).map(\.activityId) == [9, 1, 2])
}

// MARK: R-05

@Test func heldReasonIsOnlyTheWaitingForTheWatchLine() {
    #expect(decideHeldReason(fix10HeldReason) == fix10HeldReason)
    #expect(decideHeldReason("Amber (HRV 23, RHR 66): lift at current weights.") == nil)
    #expect(decideHeldReason(nil) == nil)
}

@Test @MainActor func todayCarriesTheHeldReasonForTheVerdictDate() async throws {
    let vm = TodayViewModel(provider: Fix10TodayProvider(plan: nil, reason: fix10HeldReason),
                            cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await vm.load()
    #expect(vm.heldReason == fix10HeldReason)
    let calm = TodayViewModel(provider: Fix10TodayProvider(plan: nil, reason: "Amber (HRV 23): walk."),
                              cache: OfflineCache(db: try AppDatabase.inMemory()), now: { wednesday })
    await calm.load()
    #expect(calm.heldReason == nil)
}

@Test func summaryCaptionSaysTheHeldReason() {
    #expect(daySummaryCaption(overrideCaption: nil, heldReason: fix10HeldReason) == fix10HeldReason)
    #expect(daySummaryCaption(overrideCaption: "was GO", heldReason: fix10HeldReason) == "was GO")
    #expect(daySummaryCaption(overrideCaption: nil, heldReason: nil) == nil)
}

@Test func decideWhyLineShowsTheHeldReasonEvenWithGateSignals() {
    let parts = verdictParts("GO — Day 1 Full Upper")
    #expect(decideWhyLine(verdict: parts, override: nil, hasGateSignals: true, heldReason: fix10HeldReason)
            == .held(fix10HeldReason))
    #expect(decideWhyLine(verdict: parts, override: nil, hasGateSignals: true, heldReason: nil) == nil)
    let old = verdictParts("MODIFIED (HRV low) — Walk")
    #expect(decideWhyLine(verdict: old, override: nil, hasGateSignals: false, heldReason: nil) == .reason("HRV low"))
}
