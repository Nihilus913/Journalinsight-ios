import Testing
import SwiftUI
@testable import JournalInsight

@MainActor
@Suite("PrivacyOverlay")
struct PrivacyOverlayTests {

    @Test("isRedacted returns true for non-active phases")
    func redactedForNonActive() {
        #expect(PrivacyOverlay.isRedacted(.background) == true)
        #expect(PrivacyOverlay.isRedacted(.inactive)   == true)
    }

    @Test("isRedacted returns false for active phase")
    func notRedactedForActive() {
        #expect(PrivacyOverlay.isRedacted(.active) == false)
    }
}
