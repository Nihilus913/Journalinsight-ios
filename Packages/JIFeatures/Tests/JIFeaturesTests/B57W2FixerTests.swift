import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B57-W2 fixer BUG-51 (Goals setup): the Plan band and the kcal field show plain digits like
// Nutrition ("1800–2000 kcal", "1900"), never the locale's grouping ("1'800", "1,900").
@Suite struct B57W2FixerTests {
    @Test func planBandTextHasNoGroupingSeparator() {
        #expect(goalsSetupPlanBandText((low: 1800, high: 2000)) == "1800–2000 kcal")
    }

    @Test(arguments: ["de_CH", "en_US", "fr_CH", "de_DE"])
    func goalFieldFormatHasNoGroupingInAnyLocale(_ id: String) {
        let style = goalsSetupWholeNumberFormat.locale(Locale(identifier: id))
        #expect(style.format(1900) == "1900")
        #expect(style.format(12000) == "12000")
    }
}
