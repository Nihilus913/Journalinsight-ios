import SwiftUI
import Testing
@testable import JIFeatures

/// W-FIX-P2 lane l3 (RG-21, RG-22, RG-40).
@Suite struct FixP2L3AccessibilityTests {
    /// RG-40: at the default text size "Today's session" + "Day 1 Full Upper" (+ the lift weight)
    /// do not fit on one line — the row stacks so neither text truncates.
    @Test func sessionRowStacksAtDefaultSizeWhenItCannotFit() {
        #expect(decideSessionRowStacked(.large, title: "Today's session", detail: "Day 1 Full Upper", hasLift: true))
        #expect(decideSessionRowStacked(.large, title: "Today's session", detail: "Day 1 Full Upper", hasLift: false))
        #expect(!decideSessionRowStacked(.large, title: "Today's session", detail: "Rest", hasLift: false))
        #expect(decideSessionRowStacked(.accessibility3, title: "Today's session", detail: "Rest", hasLift: false))
    }
}
