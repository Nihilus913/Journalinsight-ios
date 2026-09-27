import Testing
import JICore
@testable import JIFeatures

// W-GUI TR1 — Training (mockup 04): legend, plan line, zones card with no seeded numbers.
@Test func legendAndPlanSummary() {
    #expect(trainingStripLegend == "green = done · outline = today · grey = planned")
    #expect(trainingPlanSummary(sessionNames: ["Full Upper", "Full Upper", " Z2 60min", ""]) == "Full Upper · Z2 60min")
    #expect(trainingPlanSummary(sessionNames: []) == nil)
    #expect(trainingNextStrengthHeader(weekdayWord: "Sat") == "Next strength · Sat")
    #expect(trainingNextStrengthHeader(weekdayWord: nil) == "Next strength")
}

@Test func zonesAreUserInputNeverDefaults() {
    let rows = trainingZoneRows(cap: nil, zone2: nil)
    #expect(rows.map(\.id) == ["cap", "z2", "z5"])
    #expect(rows[0].value == "— none set" && rows[1].value == "— none set")
    #expect(rows[2].value == "—" && rows[2].subtitle == "Not a target in this plan")
    let set = trainingZoneRows(cap: 175, zone2: 135...150)
    #expect(set[0].value == "175 bpm" && set[1].value == "135–150")
    #expect(trainingProgressionCaption.hasPrefix("Double progression"))
}
