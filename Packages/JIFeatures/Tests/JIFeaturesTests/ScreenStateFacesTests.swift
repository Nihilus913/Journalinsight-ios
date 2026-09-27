import Foundation
import SwiftUI
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// W-FIX5 L5 — W-GUI-2 X2: the four state faces (mockups 57–60) as pure copy + views over
/// `ScreenState`. Copy is the mockups' verbatim; times and counts are the caller's, never invented.
struct ScreenStateFacesTests {
    // MARK: 57 — offline

    @Test func offlineCopyMarksTheLastCallAsTheLastCall() {
        let c = ScreenStateCopy.offline(lastCallAt: "07:41")
        #expect(c.pill == "Offline · last 07:41")
        #expect(c.line == "From 07:41. The hub is off your network; this is the last call, not a new one.")
        #expect(c.squares == "Your squares · as of 07:41")
        #expect(c.footer == "Weigh-ins and check-ins save on the phone and sync later. Nothing is lost by being offline.")
    }

    // MARK: 58 — first week

    @Test func firstWeekCopyCountsTheNightsAndDecidesNothing() {
        let c = ScreenStateCopy.firstWeek(nights: 4)
        #expect(c.title == "No call yet")
        #expect(c.subtitle == "Night 4 of 7")
        #expect(c.ring == "4 OF 7")
        #expect(c.body == "Your band needs seven Watch nights. Until then JI shows what it has and decides nothing.")
        #expect(c.caption == "Nothing here is a verdict. Train as you planned; the first call comes with the seventh night.")
        // Clamped: never "8 of 7", never a negative night.
        #expect(ScreenStateCopy.firstWeek(nights: 9).subtitle == "Night 7 of 7")
        #expect(ScreenStateCopy.firstWeek(nights: -1).subtitle == "Night 0 of 7")
    }

    @Test func firstWeekSignalsAreCalibratingWithTheirCounts() {
        let s = ScreenStateCopy.firstWeekSignalDetail(nights: 4, needed: 7)
        #expect(s == "4 nights · band forms at 7")
    }

    // MARK: 59 — error

    @Test func errorCopyKeepsTheLastPlanAndPointsAtTestConnection() {
        let c = ScreenStateCopy.error(what: "the plan", failedAt: "12:40", keptFrom: "07:41")
        #expect(c.title == "Couldn't load the plan")
        #expect(c.body == "The hub answered with an error at 12:40. Your last plan from 07:41 is still on the phone.")
        #expect(c.hint == "If it keeps failing: Settings › Sync & hub › Test connection.")
        // Nothing kept on the phone → say so, never a fabricated time.
        #expect(ScreenStateCopy.error(what: "the plan", failedAt: "12:40", keptFrom: nil).body
                == "The hub answered with an error at 12:40. Nothing from an earlier sync is on the phone yet.")
        #expect(ScreenStateCopy.error(what: "the plan", failedAt: nil, keptFrom: nil).body
                == "The hub answered with an error. Nothing from an earlier sync is on the phone yet.")
    }

    // MARK: 60 — no source

    @Test func noSourceCopySaysWhatWhereAndWhen() {
        let c = ScreenStateCopy.noSource(metric: "energy", needs: "resting and active energy from Apple Health",
                                         allow: "Allow both under Settings › Apple Health", firstValue: "the first balance appears after 7 clean days")
        #expect(c.title == "No energy data yet")
        #expect(c.body == "Energy needs resting and active energy from Apple Health. Allow both under Settings › Apple Health; the first balance appears after 7 clean days.")
        #expect(c.action == "Open Apple Health settings")
    }

    // MARK: faces render (both themes × schemes) and the gallery fixtures exist

    @Test @MainActor func facesRender() {
        expectRendersFeature("FirstWeekFace", height: 600) { FirstWeekFace(nights: 4) }
        expectRendersFeature("ErrorFace", height: 320) { ErrorFace(what: "the plan", failedAt: "12:40", keptFrom: "07:41", retry: {}, testConnection: {}) }
        expectRendersFeature("NoSourceFace", height: 320) {
            NoSourceFace(copy: ScreenStateCopy.noSource(metric: "energy", needs: "resting and active energy from Apple Health",
                                         allow: "Allow both under Settings › Apple Health", firstValue: "the first balance appears after 7 clean days"), openSettings: {})
        }
        expectRendersFeature("OfflineCallCard", height: 160) { OfflineCallCard(verdictWord: "MODIFIED", session: "Long Zone 2 · ~45 min easy", lastCallAt: "07:41", tint: .reduced) }
    }

    @Test func galleryFixturesCoverTheFourFaces() {
        #expect(ScreenStateFaces.registryNames == ["Today offline", "Today first week", "Today error", "Today no source"])
    }
}

/// Feature-side render smoke (JIFeatures has no `expectRenders` of its own).
@MainActor
private func expectRendersFeature<V: View>(_ name: Comment, width: CGFloat = 393, height: CGFloat = 200, @ViewBuilder _ view: () -> V) {
    for scheme in [ColorScheme.light, .dark] {
        let content = view().frame(width: width, height: height).jiTheme(.native).environment(\.colorScheme, scheme)
        #expect(ImageRenderer(content: content).cgImage != nil, "\(name) renders in \(scheme)")
    }
}
