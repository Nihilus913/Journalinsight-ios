import SwiftUI
import Testing
@testable import JIDesign
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

// W-FIX2 BUG-31: selection / CTA / links (`.info`) render in the personalization accent — green by
// default, as on the boards — not system blue. HRV keeps its own blue metric colour (`.hrv`).
@MainActor @Suite(.serialized)
struct AccentRoleTests {
    #if os(iOS) || os(tvOS) || os(visionOS)
    @Test func infoIsTheGreenAccentByDefault() {
        #expect(JIAccent.shared.color == Color(uiColor: .systemGreen))
        #expect(JITheme.native.color(.info) == Color(uiColor: .systemGreen))
        #expect(JITheme.native.color(.info) != Color(uiColor: .systemBlue))
    }

    @Test func hrvKeepsItsBlueMetricColour() {
        #expect(JITheme.native.color(.hrv) == Color(uiColor: .systemBlue))
    }
    #endif

    @Test func infoFollowsTheChosenAccent() {
        let saved = JIAccent.shared.color
        defer { JIAccent.shared.color = saved }
        JIAccent.shared.color = .teal
        #expect(JITheme.native.color(.info) == .teal)
    }

    @Test func hrvMetricTintIsNotTheAccent() {
        #expect(metricTintRole("hrv") == .hrv)
    }
}

// W-FIX2 BUG-16: the screens live in a layer BEHIND the chrome-only TabView, so they never get the
// floating tab bar in their safe area. TabTransition adds the bar's clearance as bottom safe area.
@Test func compactWidthClearsTheFloatingTabBar() {
    #expect(tabBarBottomClearance(.compact) >= 49)
}

@Test func regularWidthHasNoBottomBar() {
    #expect(tabBarBottomClearance(.regular) == 0)
}
