import SwiftUI
import Testing
@testable import JIVault

@Suite
struct PrivacyOverlayTests {
    @Test
    func activeIsNotRedacted() {
        #expect(PrivacyOverlay.isRedacted(.active) == false)
    }

    @Test
    func inactiveAndBackgroundAreRedacted() {
        #expect(PrivacyOverlay.isRedacted(.inactive) == true)
        #expect(PrivacyOverlay.isRedacted(.background) == true)
    }
}
