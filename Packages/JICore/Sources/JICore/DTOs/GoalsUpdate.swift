import Foundation

/// W4-L3 — `PUT /api/v1/planning/goals` body. Mirrors `mobile/src/data/types.ts::GoalsUpdate`
/// and HT `app/planning/router.py::GoalsUpdate/WeightGoalIn/NutritionGoalIn` exactly: every field
/// at every level is optional, and an omitted field (or an explicit null on a nested sub-field)
/// keeps its current server-side value (COALESCE semantics, see `mergeGoals` in
/// `GoalsProviding.swift`). `strength`, when provided, REPLACES the whole list. The server
/// rejects unknown keys (`extra="forbid"`), so this type only ever encodes its own declared keys.
///
/// `HubClient.send` encodes the outgoing body with a plain `JSONEncoder()` (not `JSON.encoder`'s
/// `.convertToSnakeCase` — see that method's doc comment), so every level here carries its own
/// explicit snake_case `CodingKeys` rather than relying on a global strategy. `strength` therefore
/// uses this file's own `StrengthTarget` (not JICore's top-level `StrengthGoal`, whose synthesized
/// keys are camelCase) so the wire keys are `exercise`/`target_kg` regardless of encoder strategy.
public struct GoalsUpdate: Codable, Sendable, Equatable {
    public struct WeightPatch: Codable, Sendable, Equatable {
        public var baseKg: Double?
        public var targetKg: Double?
        public var targetDate: String?
        public init(baseKg: Double? = nil, targetKg: Double? = nil, targetDate: String? = nil) {
            self.baseKg = baseKg; self.targetKg = targetKg; self.targetDate = targetDate
        }
        enum CodingKeys: String, CodingKey { case baseKg = "base_kg", targetKg = "target_kg", targetDate = "target_date" }
    }

    public struct NutritionPatch: Codable, Sendable, Equatable {
        public var kcalGoal, proteinG, carbsG, fatG: Double?
        public init(kcalGoal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
            self.kcalGoal = kcalGoal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        }
        enum CodingKeys: String, CodingKey { case kcalGoal = "kcal_goal", proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g" }
    }

    /// `strength[]` element — own type (not `StrengthGoal`) purely so this file can give it
    /// snake_case `CodingKeys` without touching `DTOs/Energy.swift` (owned by another lane).
    public struct StrengthTarget: Codable, Sendable, Equatable {
        public var exercise: String
        public var targetKg: Double
        public init(exercise: String, targetKg: Double) { self.exercise = exercise; self.targetKg = targetKg }
        enum CodingKeys: String, CodingKey { case exercise, targetKg = "target_kg" }
    }

    public var weight: WeightPatch?
    public var strength: [StrengthTarget]?
    public var stepsDaily: Int?
    public var nutrition: NutritionPatch?

    public init(weight: WeightPatch? = nil, strength: [StrengthTarget]? = nil, stepsDaily: Int? = nil, nutrition: NutritionPatch? = nil) {
        self.weight = weight; self.strength = strength; self.stepsDaily = stepsDaily; self.nutrition = nutrition
    }

    enum CodingKeys: String, CodingKey { case weight, strength, stepsDaily = "steps_daily", nutrition }
}
