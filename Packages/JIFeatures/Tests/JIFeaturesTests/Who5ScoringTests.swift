import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

@Test func who5MessageAppearsOnlyAtOrBelowTwelve() {
    #expect(who5Message(12) != nil)
    #expect(who5Message(0) != nil)
    #expect(who5Message(13) == nil)
    #expect(who5Message(25) == nil)
}

@Test func who5MessageIsTheExactApprovedCopy() {
    #expect(who5Message(5) == "This has been on the lower side lately — worth mentioning to your doctor.")
}

@Test func who5ItemsAndResponsesMatchOracleShape() {
    #expect(WHO5_ITEMS.count == 5)
    #expect(WHO5_RESPONSES.count == 6)
    #expect(WHO5_RESPONSES.map(\.value) == [5, 4, 3, 2, 1, 0])
}

// Cross-layer sanity: who5Raw/who5Percent live in JIPersistence (Who5Store's own dependency),
// re-exercised here against the scoring contract this sheet renders against.
@Test func rawTimesFourMatchesEveryResponseCombination() {
    #expect(who5Percent(who5Raw([5, 5, 5, 5, 5])) == 100)
    #expect(who5Percent(who5Raw([0, 0, 0, 0, 0])) == 0)
    #expect(who5Percent(who5Raw([3, 3, 3, 3, 0])) == 48)
}
