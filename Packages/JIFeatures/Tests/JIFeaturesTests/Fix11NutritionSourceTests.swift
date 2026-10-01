import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX11 H2-14 (bug hunt 2026-10-01): one meal, three sources — "From YAZIO via the hub" on the
// macro card, "YAZIO via Apple Health" in meal detail, "JI shows what Apple Health holds" in the
// footer, with no HealthKit at all. Meals always come from the hub's YAZIO items; the footer
// names the source the day's numbers came from.

@Test func mealDetailNamesTheHub() {
    #expect(mealDetailSourceLabel == "YAZIO via the hub")
    #expect(!mealDetailSourceLabel.contains("Apple Health"))
}

@Test func footerFollowsTheDaySource() {
    #expect(!nutritionReadOnlyNote(source: .hub).contains("Apple Health holds"))
    #expect(nutritionReadOnlyNote(source: .hub).contains("YAZIO"))
    #expect(nutritionReadOnlyNote(source: .appleHealth) == nutritionReadOnlyNote)
    #expect(nutritionReadOnlyNote(source: nil) == nutritionReadOnlyNote)
}
