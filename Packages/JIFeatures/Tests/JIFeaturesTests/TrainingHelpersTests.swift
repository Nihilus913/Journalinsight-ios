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

// MARK: - liftStepperLabel (LiftSteppers.swift) — B-28 port of the RN a11y strings asserted in
// mobile/__tests__/training/trainingScreen.render.test.tsx L47–50 and liftSteppers.celebration.test.tsx

@Test func liftStepperWeightLabelsMatchRN() {
    #expect(liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: nil, quantity: .weight, direction: .increase) == "Barbell Bench Press weight increase")
    #expect(liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: nil, quantity: .weight, direction: .decrease) == "Barbell Bench Press weight decrease")
}

@Test func liftStepperRepsLabelsMatchRNSingleSessionFixture() {
    // trainingScreen.render.test.tsx: the single-row mock fixture stays exercise_name-only.
    #expect(liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: nil, quantity: .reps, direction: .increase) == "Barbell Bench Press reps increase")
    #expect(liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: nil, quantity: .reps, direction: .decrease) == "Barbell Bench Press reps decrease")
}

@Test func liftStepperRepsLabelsCarrySessionPrefixForMultiSessionLifts() {
    // LiftSteppers.tsx L127: labelPrefix = showSessionInLabel ? `${session_name} ` : "".
    #expect(liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: "Day 1", quantity: .reps, direction: .increase) == "Day 1 Barbell Bench Press reps increase")
}

@Test func liftStepperArmedLabelAppendsTapAgainToConfirm() {
    // liftSteppers.celebration.test.tsx L168/L293: the plain label is replaced, not supplemented.
    let plain = liftStepperLabel(exerciseName: "Barbell Bench Press", sessionName: nil, quantity: .weight, direction: .decrease)
    #expect(liftStepperLabel(plain, armed: true) == "Barbell Bench Press weight decrease — tap again to confirm")
    #expect(liftStepperLabel(plain, armed: false) == plain)
}
