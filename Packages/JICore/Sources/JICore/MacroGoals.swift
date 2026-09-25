import Foundation

/// B-73: the input form of the deficit field in GoalsSetup (kcal a day, or kg a week at
/// 7700 kcal/kg). It is only used when the user asked JI to subtract a deficit.
public enum KcalMode: Codable, Sendable, Equatable {
    case deficit(kcalPerDay: Double)
    case weeklyLoss(kgPerWeek: Double)

    public static let kcalPerKg = 7700.0

    /// The deficit in kcal a day, never negative.
    public var kcalPerDay: Double {
        switch self {
        case .deficit(let kcal): max(0, kcal)
        case .weeklyLoss(let kg): max(0, kg) * Self.kcalPerKg / 7
        }
    }
}

/// B-73: the REQUIRED answer in GoalsSetup: does the typed daily goal already include the user's
/// deficit, or should JI subtract one? There is no default: the choice is always the user's.
public enum KcalGoalBasis: Codable, Sendable, Equatable {
    case includesDeficit
    case subtractDeficit(KcalMode)
}

/// B-73: the user's daily kcal goal, exactly as typed, plus how to read it.
public struct KcalGoal: Codable, Sendable, Equatable {
    public var goalKcal: Double
    public var basis: KcalGoalBasis

    public init(goalKcal: Double, basis: KcalGoalBasis) { self.goalKcal = goalKcal; self.basis = basis }

    public var deficitKcalPerDay: Double {
        switch basis {
        case .includesDeficit: 0
        case .subtractDeficit(let mode): mode.kcalPerDay
        }
    }

    /// The daily kcal target. `.includesDeficit` never subtracts again.
    public var targetKcal: Double { goalKcal - deficitKcalPerDay }

    public var isValid: Bool { goalKcal > 0 && targetKcal > 0 }
}

/// B-73: JI-owned nutrition goals, stored in `PrefStore` under `goals.macros` (`MacroGoalsStore`).
/// Every field is the user's own input and starts unset (`.unset`): JI never ships a number.
/// There are no explicit CodingKeys on purpose: `JSON.encoder`'s `.convertToSnakeCase` produces
/// `{kcal: {goal_kcal, basis}, protein_g, carbs_g, fat_g}` and the decoder reverses it. Explicit
/// snake_case keys would break that round trip (B-48). Unset fields are omitted.
public struct MacroGoals: Codable, Sendable, Equatable {
    public var kcal: KcalGoal?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?

    public init(kcal: KcalGoal? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }

    public static let unset = MacroGoals()
    public static let trackerDisclaimer = "Align your food tracker's kcal goal with this."
    public static let bandSettleNote = "The band settles after a full week of Apple Health data."
    /// What every goal slot shows while its goal is unset (never a number).
    public static let setGoalCopy = "Set your goal"

    public var isUnset: Bool { kcal == nil && proteinG == nil && carbsG == nil && fatG == nil }

    /// The kcal target (nil until the user sets a kcal goal).
    public var targetKcal: Double? { kcal?.targetKcal }

    /// The goal a KPI surface draws its tick at. nil = unset: no tick, "Set your goal".
    public func goal(for id: KpiMetricId) -> Double? {
        switch id {
        case .kcal: targetKcal
        case .protein: proteinG
        case .carbs: carbsG
        case .fat: fatG
        default: nil
        }
    }
}
