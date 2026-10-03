import SwiftUI
import Testing
@testable import JIDesign

/// W-FIX5 L5 guards (pass on the base): the chart-grammar and rule-5 contracts the W-GUI-2 rows
/// (S3, R3, X2, B-76) build on must not move while the components are reworked.
struct Fix5L5GuardTests {
    private let nights: [NormalBarPoint] = [
        .init(id: "2026-09-22", label: "Tue", value: 29, isLatest: false),
        .init(id: "2026-09-23", label: "Wed", value: nil, isLatest: false),
        .init(id: "2026-09-24", label: "Thu", value: 25, isLatest: true),
    ]

    /// Rule 5: a missing night is "—" + one reason word; the legend words the missing band.
    @Test func missingNightStaysADashPlusReasonWord() {
        #expect(normalBarSlotText(nights[1], decimals: 0) == NormalBarSlotText(value: "—", reason: "No data"))
        #expect(normalBarChartLegend(normal: nil, decimals: 0) == "your normal — Calibrating · last night")
        #expect(normalBarCaption(normal: nil, median: nil, decimals: 0) == "normal — Calibrating")
    }

    /// §4.4: the y-range follows the data and the band, never the zero floor.
    @Test func yDomainNeverStartsAtZeroForABaselineMetric() {
        let d = normalBarChartYDomain(points: nights, normal: 27...31)
        #expect(d.lowerBound > 0 && d.upperBound > 31)
    }

    /// B-57 §1: the banner is only for data older than a day; fresher data carries a pill.
    @Test func stalenessBannerOnlyAfterADay() {
        let t0 = Date(timeIntervalSince1970: 1_758_000_000)
        #expect(!stalenessBannerVisible(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(3_600)))
        #expect(stalenessBannerVisible(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(90_000)))
        #expect(!stalenessBannerVisible(fetchedAt: t0, hubReachable: true, now: t0.addingTimeInterval(90_000)))
    }

    /// Signal rows: the reference line prefers the personal normal, then the goal.
    @Test func signalReferencePrefersNormalThenGoal() {
        #expect(signalReferenceText(normal: 27...30, goal: 7, unit: "ms", decimals: 0, detail: "x") == "your normal 27–30")
        #expect(signalReferenceText(normal: nil, goal: 155, unit: "g", decimals: 0, detail: "x") == "goal 155 g")
    }

    @Test @MainActor func s3ComponentsRender() {
        expectRenders("TrendRow", height: 60) { TrendRow(name: "Resting HR", recent: 58, baseline: 60, unit: "bpm", tint: .red) }
        expectRenders("DriverBars", height: 160) { DriverBars(drivers: [DriverBar(id: "a", label: "Sleep", value: 0.7, word: "In your normal")]) }
        expectRenders("SkeletonBlock", height: 40) { SkeletonBlock(height: 16) }
    }
}
