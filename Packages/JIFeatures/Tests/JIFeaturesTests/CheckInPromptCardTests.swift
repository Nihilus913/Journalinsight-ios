import Foundation
import Testing
import SwiftUI
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
        // renders without trapping in both states
        _ = ImageRenderer(content: CheckInSheet(model: model, prompt: prompt).frame(width: 402, height: 874)).cgImage
        _ = ImageRenderer(content: CheckInPromptCard(prompt: prompt, onCheckIn: {}, onNotToday: {}).frame(width: 402)).cgImage
    }
}
