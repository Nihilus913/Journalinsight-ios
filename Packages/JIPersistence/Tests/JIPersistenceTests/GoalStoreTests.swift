import Foundation
import Testing
import JICore
@testable import JIPersistence

/// Ports `__tests__/goals/goalStore.test.ts` + `__tests__/goals/progress.test.ts` against a real
/// `AppDatabase.inMemory()` (temp-file GRDB pool) instead of the RN oracle's hand-rolled memoryDb.

@Test func addGoalThenListGoalsRoundTrips() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let id = try store.addGoal(NewGoal(title: "Bench 100kg", targetDate: "2026-12-31", progress: 0.2))
    #expect(id > 0)
    let list = try store.listGoals()
    #expect(list.count == 1)
    #expect(list[0].id == id)
    #expect(list[0].title == "Bench 100kg")
    #expect(list[0].targetDate == "2026-12-31")
    #expect(list[0].progress == 0.2)
}

@Test func addGoalSupportsNilTargetDate() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    _ = try store.addGoal(NewGoal(title: "No deadline", targetDate: nil, progress: 0))
    #expect(try store.listGoals()[0].targetDate == nil)
}

@Test func listGoalsOrdersNewestFirst() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    _ = try store.addGoal(NewGoal(title: "first"))
    _ = try store.addGoal(NewGoal(title: "second"))
    #expect(try store.listGoals().map(\.title) == ["second", "first"])
}

@Test func updateGoalUpdatesOnlyProvidedFields() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let id = try store.addGoal(NewGoal(title: "Draft title", targetDate: "2026-09-01", progress: 0.1))

    try store.updateGoal(id: id, patch: GoalPatch(title: "Final title"))
    var goal = try store.listGoals()[0]
    #expect(goal.title == "Final title")
    #expect(goal.targetDate == "2026-09-01")
    #expect(goal.progress == 0.1)

    try store.updateGoal(id: id, patch: GoalPatch(targetDate: .some(nil), progress: 0.5))
    goal = try store.listGoals()[0]
    #expect(goal.title == "Final title")
    #expect(goal.targetDate == nil)
    #expect(goal.progress == 0.5)
}

@Test func setProgressClampsBelowZeroUpToZero() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let id = try store.addGoal(NewGoal(title: "g", progress: 0.3))
    try store.setProgress(id: id, progress: -0.4)
    #expect(try store.listGoals()[0].progress == 0)
}

@Test func setProgressClampsAboveOneDownToOne() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let id = try store.addGoal(NewGoal(title: "g", progress: 0.3))
    try store.setProgress(id: id, progress: 1.7)
    #expect(try store.listGoals()[0].progress == 1)
}

@Test func updateGoalAlsoClampsProgressWhenProvided() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let id = try store.addGoal(NewGoal(title: "g", progress: 0.3))
    try store.updateGoal(id: id, patch: GoalPatch(progress: 5))
    #expect(try store.listGoals()[0].progress == 1)
}

@Test func deleteGoalRemovesTheGoal() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let keep = try store.addGoal(NewGoal(title: "keep me"))
    let gone = try store.addGoal(NewGoal(title: "delete me"))
    try store.deleteGoal(id: gone)
    let list = try store.listGoals()
    #expect(list.count == 1)
    #expect(list[0].id == keep)
}

// ---- goal_targets_mirror ----

private let sampleGoals = Goals(
    weight: WeightGoal(baseKg: 80.2, targetKg: 75.0, targetDate: "2026-10-31"),
    strength: [StrengthGoal(exercise: "bench", targetKg: 100), StrengthGoal(exercise: "row", targetKg: 100)],
    stepsDaily: 15000,
    nutrition: NutritionGoal(kcalGoal: 1800, proteinG: 172, carbsG: 160, fatG: 52)
)

@Test func loadGoalTargetsMirrorIsNilBeforeEverSaved() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    #expect(try store.loadGoalTargetsMirror() == nil)
    #expect(try store.goalTargetsMirrorSyncedAt() == nil)
}

@Test func saveThenLoadGoalTargetsMirrorRoundTripsTheFullDocument() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    try store.saveGoalTargetsMirror(sampleGoals)
    #expect(try store.loadGoalTargetsMirror() == sampleGoals)
}

@Test func saveGoalTargetsMirrorStampsSyncedAt() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    try store.saveGoalTargetsMirror(sampleGoals)
    let syncedAt = try #require(try store.goalTargetsMirrorSyncedAt())
    #expect(!syncedAt.isEmpty)
}

@Test func saveGoalTargetsMirrorIsIdempotentUpsert() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    try store.saveGoalTargetsMirror(sampleGoals)
    var updated = sampleGoals
    updated.weight.targetKg = 74.0
    try store.saveGoalTargetsMirror(updated)
    #expect(try store.loadGoalTargetsMirror() == updated)
}

@Test func adHocGoalsAndMirrorAreIndependent() throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    _ = try store.addGoal(NewGoal(title: "Bench 100kg", progress: 0.2))
    try store.saveGoalTargetsMirror(sampleGoals)

    let list = try store.listGoals()
    #expect(list.count == 1)
    #expect(list[0].title == "Bench 100kg")
    #expect(try store.loadGoalTargetsMirror() == sampleGoals)
}

// ---- progress.ts port ----

@Test func clampProgressClampsBelowZero() { #expect(clampProgress(-0.5) == 0) }
@Test func clampProgressClampsAboveOne() { #expect(clampProgress(1.5) == 1) }
@Test func clampProgressLeavesInRangeUntouched() { #expect(clampProgress(0.42) == 0.42) }
@Test func clampProgressTreatsNaNAsZero() { #expect(clampProgress(Double.nan) == 0) }

@Test func goalStatusNoTargetDateIsNeverOverdue() {
    #expect(goalStatus(targetDate: nil, progress: 0, today: "2026-08-31") == .onTrack)
    #expect(goalStatus(targetDate: nil, progress: 0.9, today: "2026-08-31") == .onTrack)
}

@Test func goalStatusPastTargetDateWithIncompleteProgressIsOverdue() {
    #expect(goalStatus(targetDate: "2026-08-30", progress: 0.5, today: "2026-08-31") == .overdue)
    #expect(goalStatus(targetDate: "2020-01-01", progress: 0, today: "2026-08-31") == .overdue)
}

@Test func goalStatusTargetDateExactlyTodayIsNotOverdue() {
    #expect(goalStatus(targetDate: "2026-08-31", progress: 0.5, today: "2026-08-31") == .onTrack)
}

@Test func goalStatusProgressExactlyOneIsCompleteEvenPastDeadline() {
    #expect(goalStatus(targetDate: "2020-01-01", progress: 1, today: "2026-08-31") == .complete)
}

@Test func goalStatusProgressAboveOneIsTreatedAsComplete() {
    #expect(goalStatus(targetDate: "2020-01-01", progress: 1.2, today: "2026-08-31") == .complete)
}
