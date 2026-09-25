import SwiftUI
import Testing
@testable import JIDesign

struct NormalBarChartTests {
    private let nights: [NormalBarPoint] = [
        .init(id: "2026-09-22", label: "Tue", value: 29, isLatest: false),
        .init(id: "2026-09-23", label: "Wed", value: nil, isLatest: false),
        .init(id: "2026-09-24", label: "Thu", value: 25, isLatest: true),
    ]

    @Test func bandPositionIsWordedNotColourOnly() {
        #expect(normalBandPosition(25, normal: 27...30) == .below)
        #expect(normalBandPosition(28, normal: 27...30) == .inside)
        #expect(normalBandPosition(31, normal: 27...30) == .above)
        #expect(normalBandPosition(nil, normal: 27...30) == nil)
        #expect(normalBandPosition(25, normal: nil) == nil)
        #expect(normalBandWord(.below) == "Below your normal")
        #expect(normalBandWord(.above) == "Above your normal")
        #expect(normalBandWord(.inside) == nil)
    }

    @Test func legendSaysCalibratingWithoutABand() {
        #expect(normalBarChartLegend(normal: nil, decimals: 0) == "your normal — Calibrating · last night")
        #expect(normalBarChartLegend(normal: 27...30, decimals: 0) == "your normal 27–30 · last night")
    }

    @Test func yAxisLeavesRoomAboveTheTallestMark() {
        #expect(normalBarChartYMax(points: nights, normal: 27...31) == 31 * 1.2)
        #expect(normalBarChartYMax(points: [], normal: nil) == 1)
    }

    @Test func accessibilityReadsEveryNightIncludingMissing() {
        #expect(normalBarChartAccessibilityLabel(points: nights, normal: 27...30, unit: "ms", decimals: 0)
                == "Tue 29 ms, Wed no data, Thu 25 ms below your normal")
    }

    /// Verifier W-B57-W1: a missing night is a visible "—" plus a reason word in its slot,
    /// not an empty gap that only VoiceOver explains.
    @Test func missingNightShowsADashAndAReasonWord() {
        #expect(normalBarSlotText(nights[0], decimals: 0) == NormalBarSlotText(value: "29", reason: nil))
        #expect(normalBarSlotText(nights[1], decimals: 0) == NormalBarSlotText(value: "—", reason: "No data"))
        let syncing = NormalBarPoint(id: "x", label: "Mon", value: nil, isLatest: false, missingReason: .notInHealthYet)
        #expect(normalBarSlotText(syncing, decimals: 0) == NormalBarSlotText(value: "—", reason: "Not in Health yet"))
        #expect(normalBarChartAccessibilityLabel(points: [syncing], normal: nil, unit: "ms", decimals: 0) == "Mon — Not in Health yet")
    }

    /// Verifier r3: at AX sizes the 7 column labels truncated ("M…", "Not in He…"); the chart
    /// switches to one full-width row per night there.
    @Test func accessibilitySizesStackOneRowPerNight() {
        #expect(!normalBarChartStacks(.large))
        #expect(!normalBarChartStacks(.xxxLarge))
        #expect(normalBarChartStacks(.accessibility1))
        #expect(normalBarChartStacks(.accessibility3))
    }

    @Test func stackedBarFractionIsValueOverTheScaleAndNilForAMissingNight() {
        #expect(normalBarFraction(18, yMax: 36) == 0.5)
        #expect(normalBarFraction(50, yMax: 36) == 1)
        #expect(normalBarFraction(nil, yMax: 36) == nil)
        #expect(normalBarFraction(5, yMax: 0) == nil)
    }

    @Test @MainActor func rendersStackedAtAccessibilitySizes() {
        expectRenders("NormalBarChart AX3", height: 700) {
            NormalBarChart(points: nights, normal: 27...30, unit: "ms").environment(\.dynamicTypeSize, .accessibility3)
        }
    }

    @Test @MainActor func renders() {
        expectRenders("NormalBarChart band", height: 220) { NormalBarChart(points: nights, normal: 27...30, unit: "ms") }
        expectRenders("NormalBarChart calibrating", height: 220) { NormalBarChart(points: nights, normal: nil, unit: "ms") }
        expectRenders("NormalBarChart empty", height: 220) { NormalBarChart(points: [], normal: nil) }
    }
}
