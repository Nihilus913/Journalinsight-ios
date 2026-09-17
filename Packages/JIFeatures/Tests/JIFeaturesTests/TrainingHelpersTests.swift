import Testing
import JICore
@testable import JIFeatures

// MARK: - trainingDayStatus (TrainingDayStrip.swift)

@Test func trainingDayStatusFutureIsAlwaysFuture() {
    #expect(trainingDayStatus(kcalBurnedActive: 1000, isFuture: true) == .future)
    #expect(trainingDayStatus(kcalBurnedActive: nil, isFuture: true) == .future)
}

@Test func trainingDayStatusNilIsNeutralNeverAJudgment() {
    #expect(trainingDayStatus(kcalBurnedActive: nil, isFuture: false) == .neutral)
}

@Test func trainingDayStatusAboveFloorIsGood() {
    #expect(trainingDayStatus(kcalBurnedActive: sessionKcalFloor, isFuture: false) == .good)
    #expect(trainingDayStatus(kcalBurnedActive: 500, isFuture: false) == .good)
}

@Test func trainingDayStatusBelowFloorIsMiss() {
    #expect(trainingDayStatus(kcalBurnedActive: 50, isFuture: false) == .miss)
    #expect(trainingDayStatus(kcalBurnedActive: 0, isFuture: false) == .miss)
}

// MARK: - orderedSessionNames (TrainingWeekStrip.swift)

private func ex(_ id: Int, _ session: String, _ name: String) -> Exercise {
    Exercise(exerciseId: id, sessionName: session, exerciseName: name, sets: 3, repsTarget: "10", currentWeightKg: 10, progressionStepKg: 1)
}

@Test func orderedSessionNamesKeepsFirstAppearanceOrderAndDedupes() {
    let rows = [ex(1, "Day 2", "A"), ex(2, "Day 1", "B"), ex(3, "Day 2", "C"), ex(4, "Day 3", "D")]
    #expect(orderedSessionNames(rows) == ["Day 2", "Day 1", "Day 3"])
}

@Test func orderedSessionNamesEmptyForNoExercises() {
    #expect(orderedSessionNames([]).isEmpty)
}

// MARK: - formatSetsReps (LiftSteppers.swift)

@Test func formatSetsRepsBothKnown() { #expect(formatSetsReps(sets: 3, reps: 10) == "3×10 reps") }
@Test func formatSetsRepsOnlySets() { #expect(formatSetsReps(sets: 3, reps: nil) == "3 sets") }
@Test func formatSetsRepsOnlyReps() { #expect(formatSetsReps(sets: nil, reps: 10) == "10 reps") }
@Test func formatSetsRepsNeitherKnown() { #expect(formatSetsReps(sets: nil, reps: nil) == "—") }
