import Testing
import JICore
import JICompute
@testable import JIFeatures

// W-GUI T5 — Why today (mockup 13): the score card is honest, the caption is the medical line,
// the BUG-29 header label survives.
@Test func scoreCardIsCalibratingWithTheNightCount() {
    // B-57 W3: the placeholder's "of 7" became the score's real 14-night need (`recoveryScoreCardText`).
    let cal = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 3)
    #expect(recoveryScoreCardText(result: cal, reasonWord: nil).caption == "Calibrating · 3 of 14 nights")
    #expect(RecoveryCardModel.note.contains("14 nights"))
}

@Test func captionAndHeaderCopy() {
    #expect(gateRationaleMedicalCaption.hasPrefix("A training call, not a medical reading."))
    #expect(gateRationaleHeaderLabel == "WHY TODAY IS")   // BUG-29
    #expect(gateRationaleNavigationTitle.isEmpty)           // BUG-33
}
