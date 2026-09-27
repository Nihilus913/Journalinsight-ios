import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B57-W5 fixer — the verifier's failures on the JIFeatures side.

private func fixerSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

/// DEV-10 icon: the NEXT card drew the runner on "Rest day" and on a strength session the phone
/// has no plan rows for. The symbol follows what the card says, not only whether rows exist.
@Test func dev10NextCardSymbolFollowsTheSession() {
    let rest = DayNextCard(session: "Rest day", prescription: nil, rows: [], exercises: nil, isRest: true)
    #expect(dayNextTemplate(card: rest) == .rest)
    #expect(dayNextTemplate(card: rest).systemImage != "figure.run")

    let strengthNoRows = DayNextCard(session: "Day 3 Full Upper", prescription: nil, rows: [],
                                     exercises: "Exercises and weights — no data")
    #expect(dayNextTemplate(card: strengthNoRows) == .strength)
    #expect(dayNextTemplate(card: strengthNoRows).systemImage == "dumbbell.fill")

    let cardio = DayNextCard(session: "easy Z2 30–40 min", prescription: nil, rows: [], exercises: nil,
                             cardio: "Zone 2 · 30–40 min · zones not set")
    #expect(dayNextTemplate(card: cardio) == .cardio)
    #expect(dayNextTemplate(card: cardio).systemImage == "figure.run")

    let row = TrainingHeroRow(id: 1, name: "Barbell Bench Press", load: "50.0 kg · 3 sets")
    let planned = DayNextCard(session: "Day 1 Full Upper", prescription: nil, rows: [row], exercises: nil)
    #expect(dayNextTemplate(card: planned) == .strength)
}

@Test func dev10RestVerdictBuildsARestCard() {
    let card = dayNextCard(verdict: verdictParts("REST — rest day"), sessionForToday: nil, override: nil)
    #expect(card.isRest)
}

/// B2: "Edit week" was a bare tinted text Button (W-GUI DEV-07: no text links).
@Test func b2EditWeekIsAButtonStyleNotATextLink() throws {
    let body = try fixerSource("Sources/JIFeatures/Training/TrainingThisWeekStrip.swift")
    let hit = try #require(body.range(of: "Button(\"Edit week\""))
    let window = String(body[hit.lowerBound...].prefix(250))
    #expect(window.contains(".buttonStyle(.jiSecondary)") || window.contains(".buttonStyle(.jiPrimary)"), "Edit week is a bare text link")
    #expect(!window.contains(".borderless"))
}
