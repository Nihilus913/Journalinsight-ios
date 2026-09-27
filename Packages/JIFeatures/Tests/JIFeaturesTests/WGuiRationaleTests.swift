import Testing
import JICore
@testable import JIFeatures

// W-GUI T5 — Why today (mockup 13): the score card is honest, the caption is the medical line,
// the BUG-29 header label survives.
@Test func scoreCardIsCalibratingWithTheNightCount() {
    #expect(gateRationaleScoreCaption(nights: 3) == "Calibrating · 3 of 7 nights")
    #expect(gateRationaleScoreCaption(nights: 12) == "Calibrating · 7 of 7 nights")
    #expect(gateRationaleScoreCaption(nights: -1) == "Calibrating · 0 of 7 nights")
    #expect(gateRationaleScoreNote.contains("7 Watch nights"))
}

@Test func captionAndHeaderCopy() {
    #expect(gateRationaleMedicalCaption.hasPrefix("A training call, not a medical reading."))
    #expect(gateRationaleHeaderLabel == "WHY TODAY IS")   // BUG-29
    #expect(gateRationaleNavigationTitle.isEmpty)           // BUG-33
}
