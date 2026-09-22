/// W3a-L1 — `GET /api/v1/nutrition/energy` + `GET /api/v1/planning/goals` wire contracts.
/// Field names/optionality mirror `mobile/src/data/types.ts::EnergyDay/EnergyReport/Goals`
/// (the RN oracle) exactly; nullable hub fields stay `Optional` here too (never default to 0 —
/// CLAUDE.md rule 5). Decoded with `JSON.decoder` (`.convertFromSnakeCase`), same as
/// `DTOs/Recovery.swift`.
public struct EnergyDay: Codable, Sendable, Equatable {
    public var date: String
    public var kcalConsumed, tdeeRaw, tdeeCorrected: Double?
    public var deficitRaw, deficitCorrected, deficitPctRaw, deficitPctCorrected: Double?
    public var deficitClass: String?
    public var mealsLogged: Int?

    public init(
        date: String,
        kcalConsumed: Double? = nil, tdeeRaw: Double? = nil, tdeeCorrected: Double? = nil,
        deficitRaw: Double? = nil, deficitCorrected: Double? = nil,
        deficitPctRaw: Double? = nil, deficitPctCorrected: Double? = nil,
        deficitClass: String? = nil, mealsLogged: Int? = nil
    ) {
        self.date = date; self.kcalConsumed = kcalConsumed; self.tdeeRaw = tdeeRaw; self.tdeeCorrected = tdeeCorrected
        self.deficitRaw = deficitRaw; self.deficitCorrected = deficitCorrected
        self.deficitPctRaw = deficitPctRaw; self.deficitPctCorrected = deficitPctCorrected
        self.deficitClass = deficitClass; self.mealsLogged = mealsLogged
    }
}

/// `app/nutrition/models.py::EnergyReport`. `tdeeEmpirical`/`goal*`/`energyAvail`/`eaWarning`
/// post-date the synced `nutrition_energy.json` fixture (adaptive-empirical-TDEE addition,
/// 2026-08-17) — absent keys decode to `nil` under the standard `JSONDecoder`, same as the RN
/// oracle's optional fields (`useComputedEnergy.ts`'s header comment).
public struct EnergyReport: Codable, Sendable, Equatable {
    public var days: [EnergyDay]
    public var avgDeficitRaw7d, avgDeficitCorrected7d, avgDeficitPct7d: Double?
    public var trackingDays: Int
    public var compliant: Bool
    public var complianceWarning: String?
    public var tdeeEmpirical: Double?
    public var goalIntakeKcal, goalProteinG, goalFatG, goalCarbsG: Double?
    public var energyAvail: Double?
    public var eaWarning: String?

    public init(
        days: [EnergyDay], avgDeficitRaw7d: Double? = nil, avgDeficitCorrected7d: Double? = nil,
        avgDeficitPct7d: Double? = nil, trackingDays: Int, compliant: Bool, complianceWarning: String? = nil,
        tdeeEmpirical: Double? = nil, goalIntakeKcal: Double? = nil, goalProteinG: Double? = nil,
        goalFatG: Double? = nil, goalCarbsG: Double? = nil, energyAvail: Double? = nil, eaWarning: String? = nil
    ) {
        self.days = days; self.avgDeficitRaw7d = avgDeficitRaw7d; self.avgDeficitCorrected7d = avgDeficitCorrected7d
        self.avgDeficitPct7d = avgDeficitPct7d; self.trackingDays = trackingDays; self.compliant = compliant
        self.complianceWarning = complianceWarning; self.tdeeEmpirical = tdeeEmpirical
        self.goalIntakeKcal = goalIntakeKcal; self.goalProteinG = goalProteinG; self.goalFatG = goalFatG
        self.goalCarbsG = goalCarbsG; self.energyAvail = energyAvail; self.eaWarning = eaWarning
    }

    // B-48: `JSON.decoder` sets `.keyDecodingStrategy = .convertFromSnakeCase`, which rewrites the
    // wire key BEFORE `CodingKeys` matching — and a snake_case segment that STARTS with a digit
    // gets its first letter upper-cased on the join (`avg_deficit_raw_7d` -> `avgDeficitRaw7D`). An
    // explicit raw value must therefore be the MANGLED spelling, never the wire string (verified
    // against a real `Foundation.JSONDecoder`). Adding one case obliges us to list every stored
    // property, so the rest are bare cases whose default raw value already equals what the
    // strategy produces.
    enum CodingKeys: String, CodingKey {
        case days
        case avgDeficitRaw7d = "avgDeficitRaw7D"
        case avgDeficitCorrected7d = "avgDeficitCorrected7D"
        case avgDeficitPct7d = "avgDeficitPct7D"
        case trackingDays, compliant, complianceWarning, tdeeEmpirical
        case goalIntakeKcal, goalProteinG, goalFatG, goalCarbsG, energyAvail, eaWarning
    }
}

/// `mobile/src/data/types.ts::WeightGoal/StrengthGoal/NutritionGoal/Goals`. `weightGoal.targetKg`
/// and `strengthGoal.targetKg` are non-null on the wire (the RN type has no `?`); the rest follow
/// the oracle's optionality verbatim.
public struct WeightGoal: Codable, Sendable, Equatable {
    public var baseKg: Double?
    public var targetKg: Double
    public var targetDate: String?
    public init(baseKg: Double? = nil, targetKg: Double, targetDate: String? = nil) {
        self.baseKg = baseKg; self.targetKg = targetKg; self.targetDate = targetDate
    }
}

public struct StrengthGoal: Codable, Sendable, Equatable {
    public var exercise: String
    public var targetKg: Double
    public init(exercise: String, targetKg: Double) { self.exercise = exercise; self.targetKg = targetKg }
}

public struct NutritionGoal: Codable, Sendable, Equatable {
    public var kcalGoal, proteinG, carbsG, fatG: Double?
    public init(kcalGoal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.kcalGoal = kcalGoal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }
}

public struct Goals: Codable, Sendable, Equatable {
    public var weight: WeightGoal
    public var strength: [StrengthGoal]
    public var stepsDaily: Int?
    public var nutrition: NutritionGoal
    public init(weight: WeightGoal, strength: [StrengthGoal], stepsDaily: Int? = nil, nutrition: NutritionGoal) {
        self.weight = weight; self.strength = strength; self.stepsDaily = stepsDaily; self.nutrition = nutrition
    }
}
