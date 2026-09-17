import Foundation

/// W4-L3 — the goals-setup screen's own write slice (reads reuse the frozen
/// `EnergyProviding.goals()`, same `GET /api/v1/planning/goals` route the Energy tab already
/// calls — see `CONTEXT-IOS-FOUNDATION.md`'s pattern of one protocol per screen's hub routes).
public protocol GoalsProviding: Sendable {
    /// `PUT /api/v1/planning/goals`
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals
}

/// `GoalsSetupView`/`GoalsSetupViewModel` need both the read (`EnergyProviding.goals()`) and the
/// write (`GoalsProviding.updateGoals`) — a single composed existential lets call sites pass one
/// provider instance (e.g. `HubDataProvider`, which conforms to both) instead of threading two.
public typealias GoalsSetupProviding = EnergyProviding & GoalsProviding

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
