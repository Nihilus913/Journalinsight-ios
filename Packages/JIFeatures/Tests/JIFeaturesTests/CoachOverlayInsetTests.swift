import SwiftUI
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

// W-GUI F8 — the overlay renders as glass and, under Reduce Transparency, as the opaque card.
@Test @MainActor func coachOverlayRendersGlassAndOpaque() {
    for rt in [false, true] {
        let view = CoachOverlayCard(change: "Swap intervals for easy Z2.", onDismiss: {})
            .jiAccessibilityOverrides(reduceTransparency: rt)
            .frame(width: 393, height: 200).jiTheme(.native)
        #expect(ImageRenderer(content: view).cgImage != nil, "coach overlay rt=\(rt)")
    }
}
