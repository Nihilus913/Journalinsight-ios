import SwiftUI
import JICore
import JICompute

/// B-73: the goals every nutrition surface draws its tick or caption against. It is injected once
/// at the app root (`EnergyBandService.snapshot`) so KpiList, KpiDetail, Trends and Nutrition
/// need no new view-model plumbing. Every goal is the user's own input: an unset goal has no tick
/// and captions "Set your goal" (rule 5, never a number). `unknown` = not injected (previews).
public nonisolated struct NutritionGoalsSnapshot: Sendable {
    public var macros: MacroGoals?

    public init(macros: MacroGoals?) { self.macros = macros }

    public static let unknown = NutritionGoalsSnapshot(macros: nil)

    /// The user's kcal target (goal, or goal − deficit).
    public var kcalGoal: Double? { macros?.targetKcal }
    /// Target ± 100. Needs no Health data.
    public var kcalBand: (low: Int, high: Int)? {
        kcalGoal.map { EnergyBand.band(targetKcal: Int($0.rounded())) }
    }

    public func goal(for id: KpiMetricId) -> Double? { macros?.goal(for: id) }

    /// KpiList square caption (board 02 KpiList / v11 item 3): macros "/ 155 g", Calories against
    /// the band, "Set your goal" for an unset goal.
    public func caption(for id: KpiMetricId, value: Double?) -> String? {
        switch id {
        case .kcal:
            guard let band = kcalBand else { return MacroGoals.setGoalCopy }
            guard let value else { return nil }
            if value < Double(band.low) { return "Under goal" }
            if value > Double(band.high) { return "Over goal" }
            return "On goal"
        case .protein, .carbs, .fat:
            return goal(for: id).map { "/ \(Int($0.rounded())) g" } ?? MacroGoals.setGoalCopy
        default:
            return nil
        }
    }
}

public extension EnvironmentValues {
    @Entry var nutritionGoals: NutritionGoalsSnapshot = .unknown
}
