import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B57-W2 L5 guard rows (scout `B-57-W2-scout.md` §2). Each test pins the invariant the fixed
// row protects, written so it holds before AND after W2 rewires Energy / Nutrition onto the
// user's own goals (B-73). PF-09 stays guarded by `Fix4L2Tests.pf09_…` (verified, unchanged).

private func source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - BUG-35: a known goal shows next to "—" on a day with no food yet, never "Goal —"

@Test func guardBUG35_goalShowsBesideAnEmptyDay() throws {
    #expect(macroHeroGoalText(1738.6) == "/ 1739 kcal")
    let status = macroKcalStatus(kcal: nil, goal: 1738.5, isToday: true)
    #expect(status == "— No data")
    #expect(!status.contains("Goal —") && !macroHeroGoalText(1738.6).contains("Goal —"))
    // RG-42 moved the goal half's words into `nutritionHeroGoalText` (B-131): with no food yet the
    // goal still shows, as "Goal 1739 kcal", never "Goal —".
    #expect(nutritionHeroGoalText(kcal: nil, goal: 1738.6) == "Goal 1739 kcal")
    #expect(nutritionHeroGoalText(kcal: 467, goal: 1738.6) == "/ 1739 kcal")
    // The hero draws the goal half in both layouts, whatever the kcal value is.
    let card = try source("Sources/JIFeatures/Nutrition/MacroSummaryCard.swift")
    #expect(card.components(separatedBy: "goalText(goal, kcal: total.kcal)").count - 1 >= 2)
    #expect(card.contains("Text(verbatim: nutritionHeroGoalText(kcal: kcal, goal: goal))"))
    let hero = try source("Sources/JIFeatures/Nutrition/RG42MissingHero.swift")
    for text in [card, hero] { #expect(!text.contains("\"Goal —\"")) }
}

// MARK: - BUG-38: "What you burn" is a measured burn or a true reason word, never 0

@Test func guardBUG38_burnIsMeasuredOrAReason() {
    let days = [EnergyDay(date: "2026-09-22", tdeeRaw: 2300, tdeeCorrected: 2200),
                EnergyDay(date: "2026-09-23", tdeeRaw: 2400),
                EnergyDay(date: "2026-09-25", tdeeRaw: 900)]            // today: still filling in
    #expect(energyBurnAverage(days: days, today: "2026-09-25") == 2350)
    // A modelled burn alone is not a measured one.
    #expect(energyBurnAverage(days: [EnergyDay(date: "2026-09-24", tdeeCorrected: 2250)], today: "2026-09-25") == nil)
    let missing = energyBurnText(days: [EnergyDay(date: "2026-09-24")], today: "2026-09-25")
    #expect(missing == "— No data")
    #expect(!missing.contains("0 kcal"))
}

// MARK: - BUG-39: "How we calculate" once; every Daily-log word is named in the explainer shown

@Test func guardBUG39_oneExplainerThatNamesTheLogWords() {
    #expect(EnergySection.allCases.filter { $0 == .howWeCalculate }.count == 1)
    let shown = energyHowWeCalculateSteps.map(\.body).joined(separator: " ")
    for s in [EnergyDayStatus.onPlan, .deepDeficit, .lightDeficit, .surplus] { #expect(shown.contains(s.word)) }
    // The log header names a band, not a single goal figure.
    #expect(energyPlanBandText(1617).hasPrefix("Plan band "))
}

// MARK: - BUG-51: nutrition numerals are plain digits, never locale-grouped ("1'183")

@Test func guardBUG51_nutritionNumeralsNeverGroup() throws {
    #expect(nutritionWholeText(1183.4) == "1183")
    #expect(nutritionWholeText(12345.6) == "12346")
    #expect(macroHeroGoalText(12345) == "/ 12345 kcal")
    #expect(nutritionWeekCaption(date: "2026-09-24", kcal: 1183.4).hasSuffix("1183 kcal"))
    // RG-42 routes the hero numeral through `nutritionHeroNumeral` (B-131): still plain digits,
    // still drawn verbatim (a LocalizedStringKey interpolation would group it).
    #expect(nutritionHeroNumeral(1183.4) == "1183")
    #expect(nutritionHeroNumeral(12345.6) == "12346")
    let hero = try source("Sources/JIFeatures/Nutrition/RG42MissingHero.swift")
    #expect(hero.contains("return nutritionWholeText(kcal)"))
    let card = try source("Sources/JIFeatures/Nutrition/MacroSummaryCard.swift")
    #expect(card.contains("if let numeral = nutritionHeroNumeral(kcal)"))
    #expect(card.contains("Text(verbatim: numeral)"))
}
