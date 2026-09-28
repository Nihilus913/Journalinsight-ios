import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI R2 — KPI detail (07 / 20 / 21): the table, the per-metric block, honest slots.
private let nights: [(date: String, value: Double?)] = (1...10).map { i in
    ("2026-09-\(String(format: "%02d", i + 10))", i == 4 ? nil : Double(20 + i))
}

@Test func tableRowsAreLastNightAverageNormalAndCount() {
    let rows = kpiDetailTableRows(history: nights, value: 30, unit: "ms", decimals: 0)
    #expect(rows.map(\.id) == ["last", "avg7", "normal", "counted"])
    #expect(rows[0].value == "30 ms")
    #expect(rows[1].subtitle == "mean of the last 7 nights")   // W-FIX6 F6-3
    #expect(rows[2].value == "— Calibrating")          // the band is W3
    #expect(rows[3].value == "9 of 10")                // the missing night stays missing
    #expect(kpiDetailTableRows(history: [], value: nil, unit: "ms", decimals: 0)[0].value == "—")
}

@Test func perMetricBlocksCarryTheHonestSlots() {
    let hrv = kpiDetailBlock(metric: .hrv, valueText: "52 ms", sleepDuration: nil)
    #expect(hrv?.title == "Same wrist, two numbers")
    #expect(hrv?.rows.map(\.value) == ["52 ms", "— not read yet", "—"])
    #expect(hrv?.caption.contains("not the same thing") == true)
    let rhr = kpiDetailBlock(metric: .rhr, valueText: "54 bpm", sleepDuration: nil)
    #expect(rhr?.title == "Not used" && rhr?.caption.contains("clinician") == true)
    let sleep = kpiDetailBlock(metric: .sleep, valueText: "81", sleepDuration: "7 h 24")
    #expect(sleep?.title == "How the score is built")
    #expect(sleep?.rows.map(\.value) == ["7 h 24", "— not read", "— not read", "— not read"])
    #expect(sleep?.caption.hasPrefix("Weights are a convention") == true)
    #expect(kpiDetailBlock(metric: .steps, valueText: nil, sleepDuration: nil) == nil)
}

@Test func subtitlesNameTheMethodAndSource() {
    #expect(kpiDetailSubtitle(.hrv) == "RMSSD · Apple Watch · while asleep")
    #expect(kpiDetailSubtitle(.rhr).hasPrefix("Overnight"))
    #expect(kpiDetailSubtitle(.sleep) == "Apple Watch · hub score")
    #expect(kpiDetailLegend.contains("Calibrating"))
}

@Test func registryCarriesTheThreeFixtures() {
    let names = ScreenRegistry.entries.map(\.name)
    #expect(names.contains("KPI detail") && names.contains("KPI detail RHR") && names.contains("KPI detail sleep"))
}
