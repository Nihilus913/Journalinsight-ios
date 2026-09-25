import Testing
import JIDesign
@testable import JIFeatures

// W-FIX2 BUG-16: the Coach overlay is pinned to the bottom of Today, which lives behind the
// chrome-only TabView — it must lift itself above the floating tab bar (its sentence was clipped).
@Test func coachOverlayClearsTheFloatingTabBarOnPhone() {
    #expect(CoachOverlayCard.bottomClearance(.compact) == tabBarBottomClearance(.compact))
    #expect(CoachOverlayCard.bottomClearance(.compact) > 0)
    #expect(CoachOverlayCard.bottomClearance(.regular) == 0)
}
