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

    // W-GUI S1 — report §4.4 chart grammar.
    @Test func yDomainFollowsTheDataNotTheZeroFloor() {
        let d = normalBarChartYDomain(points: nights, normal: 27...31)
        #expect(d.lowerBound > 0 && d.lowerBound < 25 && d.upperBound > 31)   // 25…31 ± 10 %
        #expect(normalBarChartYDomain(points: nights, normal: nil).lowerBound < 25)
        let flat = normalBarChartYDomain(points: [.init(id: "a", label: "Mon", value: 50, isLatest: true)], normal: nil)
        #expect(flat == 49...51)
        #expect(normalBarChartYDomain(points: [], normal: nil) == 0...1)
    }

    @Test func outOfBandNightsAreWordedInTheLegend() {
        #expect(normalBarChartOutOfBandWord(points: nights, normal: 27...30) == "1 night outside your normal")
        #expect(normalBarChartOutOfBandWord(points: nights, normal: 20...40) == nil)
        #expect(normalBarChartOutOfBandWord(points: nights, normal: nil) == nil)   // calibrating: no band, no word
        #expect(normalBarChartOutOfBandWord(points: nights + [.init(id: "f", label: "Fri", value: 40, isLatest: false)], normal: 27...30) == "2 nights outside your normal")
    }

    @Test func titleIsMetricWindowSource() {
        #expect(normalBarChartTitle(metric: "Overnight HRV", window: "7 nights", source: "Apple Watch") == "Overnight HRV · 7 nights · Apple Watch")
        #expect(normalBarChartTitle(metric: "Resting HR", window: "7 nights", source: nil) == "Resting HR · 7 nights")
    }

    @Test @MainActor func rendersWithMedianTitleAndSummary() {
        expectRenders("NormalBarChart median", height: 260) {
            NormalBarChart(points: nights, normal: 27...30, unit: "ms", median: 28.5, tint: .hrv,
                           title: "Overnight HRV · 7 nights · Apple Watch", summary: "Below your normal on the latest night.")
        }
    }

    @Test @MainActor func renders() {
        expectRenders("NormalBarChart band", height: 220) { NormalBarChart(points: nights, normal: 27...30, unit: "ms") }
        expectRenders("NormalBarChart calibrating", height: 220) { NormalBarChart(points: nights, normal: nil, unit: "ms") }
        expectRenders("NormalBarChart empty", height: 220) { NormalBarChart(points: [], normal: nil) }
    }
}

// W-FIX5 L5 — B-76: a missing night's "— No data" words sat in the same y-band as the lowest
// real points (the hollow tick was at the floor, 10 % under the minimum) and overlapped them.
extension NormalBarChartTests {
    /// With a missing night the domain reserves a lane under the data for the tick and its words;
    /// a complete series keeps the plain ±10 % range.
    @Test func missingNightsReserveALaneUnderTheData() {
        let complete = nights.map { NormalBarPoint(id: $0.id, label: $0.label, value: $0.value ?? 27, isLatest: $0.isLatest) }
        let plain = normalBarChartYDomain(points: complete, normal: 27...31)
        let laned = normalBarChartYDomain(points: nights, normal: 27...31)
        #expect(laned.upperBound == plain.upperBound)
        #expect(laned.lowerBound < plain.lowerBound)
        #expect(normalBarChartMissingLaneShare(points: nights, normal: 27...31) >= 0.35)
        #expect(normalBarChartMissingLaneShare(points: complete, normal: 27...31) == 0)
    }

    /// The lowest real point sits above the lane: its y fraction is at least the lane share.
    @Test func lowestPointClearsTheMissingLane() {
        let d = normalBarChartYDomain(points: nights, normal: 27...31)
        let lowest = 25.0
        let fraction = (lowest - d.lowerBound) / (d.upperBound - d.lowerBound)
        #expect(fraction > normalBarChartMissingLaneShare(points: nights, normal: 27...31))
    }

    /// The trailing axis never labels the lane (a value under the data floor would read as data).
    @Test func axisLabelsStayAboveTheDataFloor() {
        #expect(normalBarChartAxisFloor(points: nights, normal: nil) < 25)
        #expect(normalBarChartAxisFloor(points: nights, normal: nil) > normalBarChartYDomain(points: nights, normal: nil).lowerBound)
    }
}

// W-FIX5 L5 — R3 (mockup 22, report §4.4): a SUM metric (protein per day) is bars from zero
// with the goal as a dashed line; an untracked day is a hollow tick at zero, never a zero bar.
struct SumBarChartTests {
    private let days: [NormalBarPoint] = [
        .init(id: "1", label: "Fri", value: 150, isLatest: false),
        .init(id: "2", label: "Sat", value: nil, isLatest: false),
        .init(id: "3", label: "Sun", value: 132, isLatest: false),
        .init(id: "4", label: "Thu", value: 98, isLatest: true),
    ]

    @Test func yMaxIsTheTallestOfDataAndGoalWithHeadroom() {
        #expect(sumBarChartYMax(points: days, goal: 155) == 155 * 1.2)
        #expect(sumBarChartYMax(points: days, goal: nil) == 150 * 1.2)
        #expect(sumBarChartYMax(points: [], goal: nil) == 1)
    }

    @Test func legendNamesTheGoalAndTheTickForUntrackedDays() {
        #expect(sumBarChartLegend(goal: 155, unit: "g", decimals: 0) == "dashed = goal 155 g · untracked days show as a tick")
        #expect(sumBarChartLegend(goal: nil, unit: "g", decimals: 0) == "no goal set · untracked days show as a tick")
    }

    @Test func accessibilityReadsEveryDayAgainstTheGoal() {
        #expect(sumBarChartAccessibilityLabel(points: days, goal: 155, unit: "g", decimals: 0)
                == "Fri 150 g, Sat no data, Sun 132 g, Thu 98 g, goal 155 g")
        #expect(sumBarChartAccessibilityLabel(points: [days[0]], goal: nil, unit: "g", decimals: 0) == "Fri 150 g")
    }

    @Test func stackedFractionIsValueOverTheScale() {
        #expect(normalBarFraction(77.5, yMax: 155) == 0.5)
    }

    @Test @MainActor func rendersAtDefaultAndAccessibilitySizes() {
        expectRenders("SumBarChart", height: 260) { SumBarChart(points: days, goal: 155, unit: "g", tint: .protein) }
        expectRenders("SumBarChart AX3", height: 700) {
            SumBarChart(points: days, goal: 155, unit: "g", tint: .protein).environment(\.dynamicTypeSize, .accessibility3)
        }
        expectRenders("SumBarChart empty", height: 120) { SumBarChart(points: [], goal: nil, unit: "g", tint: .protein) }
    }
}

extension NormalBarChartTests {
    /// B-76: seven missing nights for one reason read as ONE "— No data" over the ticks, not seven
    /// words wall to wall; a single real night or mixed reasons keep the per-slot words.
    @Test func allMissingNightsShareOneReasonWord() {
        let none = (1...7).map { NormalBarPoint(id: "\($0)", label: "d\($0)", value: nil, isLatest: $0 == 7) }
        #expect(normalBarChartSharedMissingReason(points: none) == .noData)
        #expect(normalBarChartSharedMissingReason(points: nights) == nil)
        let mixed = none.dropLast() + [NormalBarPoint(id: "7", label: "d7", value: nil, isLatest: true, missingReason: .notInHealthYet)]
        #expect(normalBarChartSharedMissingReason(points: Array(mixed)) == nil)
        #expect(normalBarChartSharedMissingReason(points: []) == nil)
    }
}

extension SumBarChartTests {
    /// The latest value sits inside a tall bar (it collided with the goal line above one), above a short one.
    @Test func latestLabelGoesInsideATallBar() {
        #expect(sumBarChartLabelInsideBar(value: 138, yMax: 186))
        #expect(!sumBarChartLabelInsideBar(value: 20, yMax: 186))
        #expect(!sumBarChartLabelInsideBar(value: 20, yMax: 0))
    }
}
