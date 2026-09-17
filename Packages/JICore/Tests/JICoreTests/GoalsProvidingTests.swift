import Testing
@testable import JICore

/// Ports the `mergeGoals` cases from `__tests__/data/useGoals.test.tsx`.
private let sampleGoals = Goals(
    weight: WeightGoal(baseKg: 80.2, targetKg: 75.0, targetDate: "2026-10-31"),
    strength: [StrengthGoal(exercise: "bench", targetKg: 100), StrengthGoal(exercise: "row", targetKg: 100)],
    stepsDaily: 15000,
    nutrition: NutritionGoal(kcalGoal: 1800, proteinG: 172, carbsG: 160, fatG: 52)
)

@Test func mergeGoalsKeepsOmittedOrExplicitNilFieldsAtTheirCurrentValue() {
    let patch = GoalsUpdate(weight: .init(targetKg: 74, targetDate: nil))
    let merged = mergeGoals(current: sampleGoals, patch: patch)
    #expect(merged.weight.targetKg == 74)
    #expect(merged.weight.targetDate == "2026-10-31") // unchanged
    #expect(merged.weight.baseKg == 80.2) // whole nested field omitted -> unchanged
    #expect(merged.stepsDaily == 15000) // top-level section omitted -> unchanged
    #expect(merged.nutrition.proteinG == 172) // unchanged
}

@Test func mergeGoalsProvidedStrengthReplacesTheWholeListNotPerExerciseMerge() {
    let patch = GoalsUpdate(strength: [.init(exercise: "bench", targetKg: 105)])
    let merged = mergeGoals(current: sampleGoals, patch: patch)
    #expect(merged.strength == [StrengthGoal(exercise: "bench", targetKg: 105)])
}

@Test func mergeGoalsEmptyPatchLeavesEveryFieldUnchanged() {
    let merged = mergeGoals(current: sampleGoals, patch: GoalsUpdate())
    #expect(merged == sampleGoals)
}
