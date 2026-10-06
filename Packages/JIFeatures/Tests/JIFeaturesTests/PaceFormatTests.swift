import Foundation
import Testing
import JIDesign
@testable import JIFeatures

/// RG-33 (B-94): the Runs · Pace chart's y-axis ticks and "avg" rule read m:ss /km, never raw
/// seconds per km ("1 000", "avg 623") next to a formatted "9:04 /km" headline.
@Suite struct PaceFormatTests {
    @Test func paceFormatsMinutesSeconds() {
        #expect(ProgressFormat.pace(543.8) == "9:04")
        #expect(ProgressFormat.pace(623) == "10:23")
    }

    @Test func paceChartAxisAndAverageUseMinutesSeconds() throws {
        let fmt = try #require(ProgressFormat.chartValueFormat(.run(.pace)))
        #expect(fmt(623) == "10:23")
        #expect(fmt(543.8) == "9:04")
        #expect(fmt(1000) == "16:40")
        #expect(TrendChart.averageLabel(623, format: fmt) == "avg 10:23")
    }

    @Test func otherMetricsKeepPlainNumbers() {
        #expect(ProgressFormat.chartValueFormat(.run(.hr)) == nil)
        #expect(TrendChart.averageLabel(152.4, format: nil) == "avg 152")
    }
}
