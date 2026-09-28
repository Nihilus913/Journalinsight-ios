import SwiftUI
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI T1 — Decide (mockups 01 / 10): hero tint = the verdict role, exactly one primary
// button, the readiness ring's honest reason when the score is nil.
@Test func heroTintIsTheVerdictRoleAndNoneWhileSyncing() {
    #expect(decideHeroTintRole(tone: .go, syncing: false) == .go)
    #expect(decideHeroTintRole(tone: .amber, syncing: false) == .reduced)
    #expect(decideHeroTintRole(tone: .red, syncing: false) == .danger)
    #expect(decideHeroTintRole(tone: .amber, syncing: true) == nil)
}

@Test func exactlyOnePrimaryButton() {
    #expect(decideButtonRoles(showsAdjust: true).filter { $0 == .primary }.count == 1)
    #expect(decideButtonRoles(showsAdjust: false) == [.primary])
    #expect(decideGoForeground == .black)   // BUG-30: black on the accent
}

@Test func readinessRingReasonWhenTheScoreIsMissing() {
    #expect(decideReadinessCaption(score: nil, nights: 3) == "Readiness needs 7 overnight nights · 3 of 7 so far · Calibrating")
    #expect(decideReadinessCaption(score: nil, nights: nil) == "Readiness needs 7 overnight nights · 0 of 7 so far · Calibrating")
    // W-FIX6 F6-11: a met count is never "7 of 7 so far · Calibrating".
    #expect(decideReadinessCaption(score: nil, nights: 12) == "Readiness · No data")
    #expect(decideReadinessCaption(score: 72, nights: 9) == "Readiness")
    #expect(decideHrvFootnote.contains("RMSSD") && decideHrvFootnote.contains("SDNN"))
}

@Test @MainActor func readinessRingRenders() {
    for score in [nil, 72.0] {
        let v = DecideReadinessRing(score: score, nights: 3).frame(width: 200, height: 140).jiTheme(.native)
        #expect(ImageRenderer(content: v).cgImage != nil)
    }
}
