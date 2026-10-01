import Foundation
import Testing
import JICore
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
