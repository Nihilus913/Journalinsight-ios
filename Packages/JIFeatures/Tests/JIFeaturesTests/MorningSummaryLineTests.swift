import Testing
import Foundation
import JICore
@testable import JIFeatures

@Suite struct MorningSummaryLineTests {
    @Test func joinsWordSessionReadiness() {
        #expect(morningSummaryText(verdict: verdictParts("GO — Full Upper"), readiness: 78) == "GO · Full Upper · readiness 78")
        #expect(morningSummaryText(verdict: verdictParts("REST"), readiness: nil) == "REST")
        #expect(morningSummaryText(verdict: verdictParts(nil), readiness: 60) == "— · No verdict yet · readiness 60")
    }
}
