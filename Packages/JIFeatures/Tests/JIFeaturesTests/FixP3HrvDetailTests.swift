import Foundation
import Testing
import JICompute
import JIDesign
@testable import JIFeatures

// W-FIX-P3 RG-82 (B-104): HRV detail polish — the 28-night count leaves today out, the legend only
// names what is drawn and "dashed" means one thing (Garmin), the 7 D chart is not smoothed, and a
// night is painted outside the band only when it is outside at the precision the screen shows.

private func day(_ i: Int) -> String {
    let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 1).date!)!
    let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

@Suite struct FixP3HrvDetailTests {
    @Test func countedLeavesTodayOut() {
        // 29 dated nights, the newest is today: the window is the 28 nights before today.
        let history: [(date: String, value: Double?)] = (0...28).map { i in (day(i), i % 3 == 0 ? nil : 30) }
        let today = day(28)
        let rows = kpiDetailTableRows(history: history, value: 30, unit: "ms", decimals: 0, normal: nil, today: today)
        let expected = (0..<28).filter { $0 % 3 != 0 }.count
        #expect(rows.first { $0.id == "counted" }?.value == "\(expected) of 28")
        // Without `today` the old window is unchanged (other metrics).
        let old = kpiDetailTableRows(history: history, value: 30, unit: "ms", decimals: 0)
        #expect(old.first { $0.id == "counted" }?.value == "\((1...28).filter { $0 % 3 != 0 }.count) of 28")
    }

    @Test func legendNamesOnlyWhatIsDrawn() {
        // No band yet: nothing shaded and no median line is drawn, so the legend names neither.
        #expect(!kpiDetailLegendText(nil, decimals: 0).contains("shaded"))
        #expect(!kpiDetailLegendText(nil, decimals: 0).contains("median"))
        #expect(kpiDetailLegendText(nil, decimals: 0).contains("Calibrating"))
        // With a band: the median line is dotted, so "dashed" is left to the Garmin nights alone.
        let n = PersonalNormalResult(median: 28.4, low: 25.2, high: 31.6, sd: 2, n: 22)
        let legend = kpiDetailLegendText(n, decimals: 0) + " · " + kpiHrvGarminLegend
        #expect(legend.components(separatedBy: "dashed").count - 1 == 1)
        #expect(legend.contains("dotted = median 28"))
    }

    @Test func sevenDayChartIsNotSmoothed() {
        #expect(kpiTrendSmoothed(.week) == false)
        #expect(kpiTrendSmoothed(.month))
        #expect(kpiTrendSmoothed(.quarter))
    }

    @Test func bandPositionUsesShownPrecision() {
        // Band 23.4–28.3 is shown "23–28"; a 23.2 ms night is shown "23" — inside, not amber.
        let band = 23.4...28.3
        #expect(normalBandPosition(23.2, normal: band, decimals: 0) == .inside)
        #expect(normalBandPosition(22.4, normal: band, decimals: 0) == .below)
        #expect(normalBandPosition(28.4, normal: band, decimals: 0) == .inside)
        #expect(normalBandPosition(28.6, normal: band, decimals: 0) == .above)
        let pts = [NormalBarPoint(id: "a", label: "Mon", value: 23.2, isLatest: false), NormalBarPoint(id: "b", label: "Tue", value: 22.0, isLatest: true)]
        #expect(normalBarChartOutOfBandWord(points: pts, normal: band, decimals: 0) == "1 night outside your normal")
    }
}
