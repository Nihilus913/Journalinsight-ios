import Foundation
import SwiftUI
import Testing
import JIDesign
@testable import JIFeatures

/// W-FIX-P3 lane l1: sim-rendered proof shots (the iOS Simulator test runner's ImageRenderer) for
/// RG-55 (Strain bar at 0 and with the 19–49 band) and RG-56 (Decide after the user's call). PNGs go
/// to `FIXP3_SHOTS` (passed as TEST_RUNNER_FIXP3_SHOTS) when set; the render is asserted either way.
@Suite @MainActor struct FixP3L1RenderShotsTests {
    func render<V: View>(_ name: String, _ view: V, height: CGFloat = 220) -> Bool {
        let r = ImageRenderer(content: view.jiTheme(.native).environment(\.jiOffscreenRender, true)
            .frame(width: 402, height: height).background(Color(white: 0.95)))
        r.scale = 3
        guard let img = r.uiImage, let png = img.pngData() else { return false }
        if let dir = ProcessInfo.processInfo.environment["FIXP3_SHOTS"], !dir.isEmpty {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return true
    }

    @Test func rg55StrainAtZeroAndInBand() {
        let cards: [(String, DecideStrainState)] = [
            ("rg55-strain-before-0", .before(value: 0, usual: 19...49, position: .below, caption: "Yesterday was a rest day.")),
            ("rg55-strain-before-30", .before(value: 30, usual: 19...49, position: .inside, caption: "Inside your usual.")),
            ("rg55-strain-after-0-max60", .after(value: 0, maxToday: 60, roomLeft: 60, caption: "A limit, not a goal.")),
        ]
        for (name, state) in cards {
            #expect(render(name, DecideStrainCard(state: state).padding(16)))
        }
    }

    /// The after-call fixture moved to today (its override was made at 13:25 local), so the kicker
    /// is today's: "YOUR CALL · 13:25", not the hub's 05:10 compute time.
    @Test func rg56DecideAfterTheUsersCall() throws {
        let today = RecoveryInsightService.localDayKey(Date())
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "xxx"
        let off = f.string(from: Date())
        let json = fixtureMorningAfterCallJSON
            .replacingOccurrences(of: "\"created_at\":\"2026-09-21T07:45:00+02:00\"", with: "\"created_at\":\"\(today)T13:25:00\(off)\"")
            .replacingOccurrences(of: "2026-09-21", with: today)
        let model = try #require(TodayViewModel.fixture(morningState: .decide, morningJSON: json))
        #expect(render("rg56-decide-after-call-today", TodayView(model: model, onOpenConnection: {}), height: 874))
    }
}
