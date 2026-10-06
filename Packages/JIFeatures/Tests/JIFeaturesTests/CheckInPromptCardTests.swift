import Foundation
import Testing
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import JICore
import JIPersistence
@testable import JIFeatures

// W-B102 C-4 — the Today card copy and the sheet's optional "Why this prompt" strip.

@MainActor
struct CheckInPromptCardTests {
    private let prompt = CheckInPrompt(
        rule: .amber2, day: DayKey(iso: "2026-10-04")!, title: "Two amber mornings in a row",
        body: "Oct 3 Modified, Oct 4 Rest. How do you feel? 10 seconds.",
        why: "Two mornings without a GO (Oct 3 Modified, Oct 4 Rest). Your answer is stored with today's date only; it does not change the verdict.",
        morningsLine: "GO · GO · Modified · Rest → amber ×2")

    @Test func cardCopy() {
        let c = CheckInPromptCardContent(prompt)
        #expect(c.title == "Two amber mornings in a row")
        #expect(c.morningsLine == "Mornings GO · GO · Modified · Rest → amber ×2")
        #expect(c.primary == "Check in · 10 s")
        #expect(c.secondary == "Not today")
        #expect(c.footer == "Asked at most once a day. A check-in never changes the verdict, the gate or dosing.")
    }

    @Test func sheetWhyStripOnlyWithAPrompt() throws {
        let db = try AppDatabase.inMemory()
        let model = MindViewModel(checkins: CheckInStore(db: db), eventStore: EventStore(db: db), who5Store: Who5Store(db: db))
        #expect(!CheckInSheet(model: model).showsWhy)
        #expect(CheckInSheet(model: model, prompt: prompt).showsWhy)
        // renders without trapping in both states. The sheet is NavigationStack-rooted, so it goes
        // through a hosting controller in a window: `ImageRenderer` cannot flatten the UIKit-backed
        // NavigationStack and SwiftUI traps ("no current update to enqueue action to"), which killed
        // the whole JIFeatures run and left xcodebuild hung in diagnostics collection (B-116).
        #expect(hostedRender(CheckInSheet(model: model).frame(width: 402, height: 874)))
        #expect(hostedRender(CheckInSheet(model: model, prompt: prompt).frame(width: 402, height: 874)))
        #expect(ImageRenderer(content: CheckInPromptCard(prompt: prompt, onCheckIn: {}, onNotToday: {}).frame(width: 402)).cgImage != nil)
    }

    /// `ScreenSweepTests.sweepImage`'s route: a window (never `makeKeyAndVisible` — no host app),
    /// a layout pass and a flush, then `drawHierarchy`. True when the hierarchy laid out and drew.
    private func hostedRender(_ view: some View) -> Bool {
        #if canImport(UIKit) && !os(watchOS)
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view)
        host.view.frame = bounds
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        CATransaction.flush()
        let image = UIGraphicsImageRenderer(size: bounds.size).image { ctx in
            if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
        }
        window.isHidden = true
        window.rootViewController = nil
        return image.size == bounds.size
        #else
        return true // macOS `swift test`: no UIKit window route; the sim run covers it
        #endif
    }
}
