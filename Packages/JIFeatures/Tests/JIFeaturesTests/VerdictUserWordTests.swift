import Testing
import JICore
@testable import JIFeatures

/// B-57 W1 r5 — one source of truth for the verdict's user-facing word (boards: Decide
/// "Full", GateRationale "Why today is Full", the Last 3 days table "Full" / "Modified").
@Test(arguments: [
    ("GO — Full Upper", "Full"),
    ("GO (auto-regulated) — Day 3", "Modified"),   // W-FIX1 BUG-03: amber = trimmed
    ("FULL", "Full"),
    ("REDUCED (sleep) — deload dose, not a day off", "Modified"),
    ("MODIFIED (HRV low) — Easy Z2", "Modified"),
    ("RED — walk only", "Rest"),
    ("REST", "Rest"),
])
func theHubWordBecomesTheUserWord(raw: String, word: String) {
    #expect(verdictUserWord(verdictParts(raw)) == word)
}

@Test func noVerdictStaysTheDash() {
    #expect(verdictUserWord(verdictParts(nil)) == "—")
}

/// A word the map does not know is shown as sent, never guessed into Full/Modified/Rest.
@Test func anUnknownWordPassesThrough() {
    #expect(verdictUserWord(verdictParts("INSUFFICIENT_DATA")) == "INSUFFICIENT_DATA")
}

/// The three words are the ones GateConfig's "How the morning call works" card explains.
@Test func theWordsAreGateConfigsWords() {
    #expect(gateConfigMorningCallRows.map(\.word) == [VerdictUserWord.full, VerdictUserWord.modified, VerdictUserWord.rest])
}

/// Decide's big word is the same mapping.
@Test func decideUsesTheSameWord() {
    for raw in ["GO — x", "REDUCED — y", "RED — z", "MODIFIED (HRV low)"] {
        #expect(decideWord(verdictParts(raw)) == verdictUserWord(verdictParts(raw)))
    }
}
