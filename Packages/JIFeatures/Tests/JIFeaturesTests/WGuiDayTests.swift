import SwiftUI
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI T3 — Day (mockup 02): chevron rows, NEXT templates, one tile size, honest captions.
@Test func footerRowsAreChevronRowsNotLinks() {
    #expect(DayFooterRow.allCases.map(\.title) == ["Trends", "Week review"])
    #expect(DayFooterRow.weekReview.value == "— not counted yet")   // W5 owns the count (plan §B)
    for row in DayFooterRow.allCases { #expect(!row.systemImage.isEmpty) }
}

@Test func nextTemplateIsCardioWithoutPlanRowsAndStrengthWithThem() {
    #expect(dayNextTemplate(rows: []) == .cardio)   // "easy Z2 30–40 min" matches no plan session
    let row = TrainingHeroRow(id: 1, name: "Barbell Bench Press", load: "50.0 kg · 3 sets")
    #expect(dayNextTemplate(rows: [row]) == .strength)
}

@Test func tileFamiliesAreOneSize() {
    #expect(JITileHeight.macroTile.base == 96)
    #expect(JITileHeight.square.base == 172)
}

@Test func fuelCaptionsAreHonest() {
    #expect(dayFuelLeftText(kcal: 1183, goal: 1617) == "434 left · your goal")
    #expect(dayFuelLeftText(kcal: 1700, goal: 1617) == "83 over · your goal")
    #expect(dayFuelLeftText(kcal: 1183, goal: nil) == nil)
    #expect(dayMacroCaption(label: "Protein", value: 98, goal: 155) == "Protein · goal 155")
    #expect(dayMacroCaption(label: "Carbs", value: 118, goal: nil) == "Carbs")
    #expect(dayMacroCaption(label: "Fat", value: nil, goal: 60) == "Fat · No data")
    // DEV-09 label half: the HRV square's caption names the method; the title stays short.
    #expect(todayCardCaption(TodayChip(id: "hrv", label: "HRV", value: 25, unit: "ms", points: [], sourceMissing: false, asOf: "as of 26 Sep")) == "as of 26 Sep · RMSSD · overnight")
    #expect(todayCardCaption(TodayChip(id: "hrv", label: "HRV", value: 25, unit: "ms", points: [], sourceMissing: false)) == nil)
    #expect(todayCardCaption(TodayChip(id: "rhr", label: "Resting HR", value: 52, unit: "bpm", points: [], sourceMissing: false, asOf: "as of 26 Sep")) == "as of 26 Sep")
}
