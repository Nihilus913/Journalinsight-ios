import Testing
@testable import JIFeatures

// W-GUI J1 — Journal (mockup 09): copy and the mood tile, pure.
@Test func journalCopyAndTiles() {
    #expect(journalStreakCaption == "Missing a day does not reset anything")
    #expect(journalPromptTags == ["Sleep timing", "Work stress", "Late meal", "Alcohol", "Illness"])
    #expect(journalMoodTileText(score: 3) == "3/5")
    #expect(journalMoodTileText(score: nil) == "—")
    #expect(journalLocalCaption.hasPrefix("Journal and Mind live on the device."))
}
