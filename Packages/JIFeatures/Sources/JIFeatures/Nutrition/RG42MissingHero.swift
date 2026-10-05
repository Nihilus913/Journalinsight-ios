import Foundation

// RG-42: a missing hero value used to render "—" in the heavy display numeral, which reads as a
// stuck skeleton bar next to "/ 1935 kcal" (Nutrition) and "kcal a day" (Energy 7-day balance).
// Rule 5 still holds (never a zero): the missing state is words, not a dash numeral.

/// The Nutrition hero numeral, or nil when nothing is logged (the view then draws no numeral).
public nonisolated func nutritionHeroNumeral(_ kcal: Double?) -> String? {
    guard let kcal, kcal.isFinite else { return nil }
    return nutritionWholeText(kcal)
}

/// The hero's goal half. With a value: "/ 1935 kcal"; without one it stands alone: "Goal 1935 kcal".
public nonisolated func nutritionHeroGoalText(kcal: Double?, goal: Double?) -> String {
    if nutritionHeroNumeral(kcal) != nil { return macroHeroGoalText(goal) }
    guard let goal, goal.isFinite, goal > 0 else { return "No kcal logged" }
    return "Goal \(nutritionWholeText(goal)) kcal"
}

/// The YESTERDAY card's title, shown whether or not the day has a value.
public nonisolated func nutritionPreviousDayCardTitle(_ unit: String) -> String {
    unit == "kcal" ? "Calories" : "Protein"
}

/// The Energy hero numeral, or nil without a 7-day balance.
public nonisolated func energyHeroNumeralOrNil(_ deficit: Double?) -> String? {
    guard let deficit, deficit.isFinite else { return nil }
    return energyHeroNumeral(deficit)
}

public nonisolated let energyHeroMissingText = "No 7-day balance yet"
