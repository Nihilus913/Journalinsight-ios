import Foundation
import Testing
import JICore
import JICompute
@testable import JIFeatures

// W-FIX11 H2-04 (bug hunt 2026-10-01): RHR / Sleep detail say "Apple Watch", but the 28-day
// average and "Nights counted 27 of 28" mixed Garmin nights (≈ 61 bpm) with Apple nights
// (≈ 70 bpm). The baseline now reads only the nights the labelled source (Apple, the hub's
// `/vitals/recovery-inputs`) has for the metric.

private let garmin = (1...12).map { String(format: "2026-09-%02d", $0) }
private let apple = (13...30).map { String(format: "2026-09-%02d", $0) }

private var mixed: [(date: String, value: Double?)] {
    garmin.map { ($0, 61.0) } + apple.map { ($0, 70.0) }
}
private var appleInputs: [RecoveryInputDay] {
    garmin.map { RecoveryInputDay(date: $0) } + apple.map { RecoveryInputDay(date: $0, hrvMs: 40, rhrBpm: 70, sleepH: 7) }
}

@Test func rhrBaselineReadsOnlyAppleNights() {
    let h = kpiSourceFilteredHistory(mixed, metric: .rhr, sourceDays: appleInputs)
    #expect(h.count == mixed.count)                                  // the days stay; Garmin values go
    #expect(h.compactMap(\.value).allSatisfy { $0 == 70 })
    #expect(h.compactMap(\.value).count == apple.count)
    let status = kpiDetailStatus(history: h, value: 70, unit: "bpm", decimals: 0)
    #expect(status.word == "Steady")                                 // never "Down" against a Garmin-mixed 69
    #expect(status.detail.contains("70 bpm"))
}

@Test func sleepBaselineReadsOnlyNightsWithAppleSleep() {
    let h = kpiSourceFilteredHistory(mixed, metric: .sleep, sourceDays: appleInputs)
    #expect(h.compactMap(\.value).count == apple.count)
}

@Test func noSourceDaysKeepsTheHistory() {
    #expect(kpiSourceFilteredHistory(mixed, metric: .rhr, sourceDays: []).compactMap(\.value).count == mixed.count)
    #expect(kpiSourceFilteredHistory(mixed, metric: .steps, sourceDays: appleInputs).compactMap(\.value).count == mixed.count)
}

@Test func theTableCountsTheSameNights() {
    let h = kpiSourceFilteredHistory(mixed, metric: .rhr, sourceDays: appleInputs)
    let rows = kpiDetailTableRows(history: h, value: 70, unit: "bpm", decimals: 0, isNightly: true)
    #expect(rows.first { $0.id == "counted" }?.value == "18 of 28")
}

// W-FIX11 H2-09: no direction word while the hub calibrates, under 14 readings (the hub's own
// count), or on an old reading ("Up" on a 16-day-old Readiness).
private func series(_ n: Int, _ v: Double) -> [(date: String, value: Double?)] {
    (1...n).map { (date: String(format: "2026-09-%02d", $0), value: v) }
}

@Test func calibratingHubMeansNoDirection() {
    let s = kpiDetailStatus(history: series(20, 23), value: 23, unit: "ms", decimals: 0, hubCalibrating: true)
    #expect(s.word == "— Calibrating")
}

@Test func thirteenReadingsIsStillCalibrating() {
    #expect(kpiDetailStatus(history: series(13, 50), value: 50, unit: "ms", decimals: 0).word == "— Calibrating")
    #expect(kpiDetailStatus(history: series(14, 50), value: 50, unit: "ms", decimals: 0).word == "Steady")
}

@Test func anOldReadingGetsNoDirection() {
    let s = kpiDetailStatus(history: series(20, 50), value: 60, unit: "", decimals: 0,
                            valueDate: "2026-09-15", today: "2026-10-01")
    #expect(s.word.hasPrefix("—"))
    #expect(s.detail.contains("15 Sep"))
}

// W-FIX11 H1-16: one number format on KPI detail — hero, status line, table, normal and axis all
// group like the Targets rows ("4,179", "15,000 steps"), never "4'179" beside "7826".
@Test func kpiDetailNumbersShareOneFormat() {
    #expect(kpiDetailNumber(4179, decimals: 0) == "4,179")
    #expect(kpiDetailNumber(nil, decimals: 0) == "—")
    #expect(kpiAxisNumber(20000) == "20,000")
    let h: [(date: String, value: Double?)] = (1...20).map { (date: String(format: "2026-09-%02d", $0), value: 7826) }
    #expect(kpiDetailStatus(history: h, value: 7826, unit: "steps", decimals: 0).detail.contains("7,826 steps"))
    let rows = kpiDetailTableRows(history: h, value: 4179, unit: "steps", decimals: 0, isNightly: false,
                                  normal: PersonalNormalResult(median: 7000, low: 4742, high: 9379, sd: 1, n: 20))
    #expect(rows.first { $0.id == "last" }?.value == "4,179 steps")
    #expect(rows.first { $0.id == "avg7" }?.value == "7,826 steps")
    #expect(rows.first { $0.id == "normal" }?.value == "4,742–9,379 steps")
}
