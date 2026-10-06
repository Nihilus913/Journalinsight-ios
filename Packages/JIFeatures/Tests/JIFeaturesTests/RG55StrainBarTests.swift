import Foundation
import Testing
@testable import JIFeatures

/// RG-55: Decide's Strain bar draws nothing for a 0 value and puts its band / max label under the
/// band or marker instead of centring it between Spacers.
@Suite struct RG55StrainBarTests {
    @Test func zeroValueDrawsNoFill() {
        #expect(decideStrainFillWidth(value: 0, width: 300) == nil)
        #expect(decideStrainFillWidth(value: -3, width: 300) == nil)
        #expect(decideStrainFillWidth(value: 0.5, width: 300) == 4)
        #expect(decideStrainFillWidth(value: 50, width: 300) == 150)
        #expect(decideStrainFillWidth(value: 140, width: 300) == 300)
    }

    @Test func labelSitsUnderBandOrMarker() throws {
        let band = try #require(decideStrainBarLabel(band: 19...49, marker: nil))
        #expect(band.text == "19–49" && band.center == 34)
        #expect(abs(decideStrainLabelX(center: band.center, width: 300) - 102) < 0.001)
        let max = try #require(decideStrainBarLabel(band: nil, marker: 60))
        #expect(max.text == "max 60")
        #expect(abs(decideStrainLabelX(center: max.center, width: 300) - 180) < 0.001)
        #expect(decideStrainBarLabel(band: nil, marker: nil) == nil)
    }

    @Test func labelStaysClearOfTheEndLabels() {
        #expect(decideStrainLabelX(center: 2, width: 300) == 32)
        #expect(decideStrainLabelX(center: 99, width: 300) == 268)
        #expect(decideStrainLabelX(center: 50, width: 40) == 20)
    }
}
