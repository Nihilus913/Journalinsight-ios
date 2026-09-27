import Testing
@testable import JIFeatures

// W-GUI M3 — Energy (mockup 06): the section order stays the board's; the caption is the estimate line.
@Test func energySectionsAndCaption() {
    #expect(EnergySection.allCases == [.hero, .whatYouBurn, .howWeCalculate, .thisWeek])
    #expect(energyNoJudgementCaption == "Energy expenditure from a wrist sensor is an estimate. No medical judgement is made here.")
    #expect(energyHeroNumeral(nil) == "—")   // rule 5: never a zero for a missing balance
}
