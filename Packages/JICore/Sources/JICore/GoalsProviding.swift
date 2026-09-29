import Foundation

/// W-FIX10 F10-1 (audit 03-F1): the goals screen reads the hub's goals document
/// (`EnergyProviding.goals()`, `GET /api/v1/planning/goals`) and writes nothing to the hub
/// directly — weight / strength / steps go into the phone's `TargetsStore` and reach the hub as
/// the ONE targets body (outbox kind `targets`, `PUT /planning/targets`). The old write slice
/// `GoalsProviding.updateGoals` (`PUT /planning/goals`, removed hub-side → a 405 on every save,
/// replayed forever from the outbox) is gone.
public typealias GoalsSetupProviding = EnergyProviding

/// Port of `mobile/src/data/useGoals.ts::mergeGoals` — applies a `GoalsUpdate` patch the same way
/// the server does (`app.planning.service.update_goals`): an omitted or explicit-nil field at any
/// level keeps its current value; `strength`, when provided, REPLACES the whole list.
public func mergeGoals(current: Goals, patch: GoalsUpdate) -> Goals {
    let w = patch.weight
    let n = patch.nutrition
    return Goals(
        weight: WeightGoal(
            baseKg: w?.baseKg ?? current.weight.baseKg,
            targetKg: w?.targetKg ?? current.weight.targetKg,
            targetDate: w?.targetDate ?? current.weight.targetDate
        ),
        strength: patch.strength.map { $0.map { StrengthGoal(exercise: $0.exercise, targetKg: $0.targetKg) } } ?? current.strength,
        stepsDaily: patch.stepsDaily ?? current.stepsDaily,
        nutrition: NutritionGoal(
            kcalGoal: n?.kcalGoal ?? current.nutrition.kcalGoal,
            proteinG: n?.proteinG ?? current.nutrition.proteinG,
            carbsG: n?.carbsG ?? current.nutrition.carbsG,
            fatG: n?.fatG ?? current.nutrition.fatG
        )
    )
}
