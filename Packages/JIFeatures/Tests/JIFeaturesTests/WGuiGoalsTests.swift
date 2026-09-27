import Testing
@testable import JIFeatures

// W-GUI M4 — Goals (39): the hero's progress bar is honest; the caption says targets are the user's.
@Test func progressFractionNeedsAllThreeNumbers() {
    #expect(goalsProgressFraction(startText: "80.4 kg", latestKg: 79.5, targetText: "75.0") == (80.4 - 79.5) / (80.4 - 75.0))
    #expect(goalsProgressFraction(startText: "— kg", latestKg: 79.5, targetText: "75.0") == nil)
    #expect(goalsProgressFraction(startText: "80.4 kg", latestKg: nil, targetText: "75.0") == nil)
    #expect(goalsProgressFraction(startText: "75.0 kg", latestKg: 75, targetText: "75.0") == nil)
    #expect(goalsProgressFraction(startText: "80.0 kg", latestKg: 70, targetText: "75.0") == 1)
    #expect(goalsYoursCaption.hasPrefix("Targets are yours to set"))
}
