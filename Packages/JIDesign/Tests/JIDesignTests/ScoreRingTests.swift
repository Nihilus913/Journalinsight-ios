import SwiftUI
import Testing
@testable import JIDesign

@Test @MainActor func scoreRingRenders() {
    expectRenders("ScoreRing", width: 80, height: 80) { ScoreRing(value: 72, max: 100, tint: .purple) }
    expectRenders("ScoreRing empty", width: 80, height: 80) { ScoreRing(value: 0, max: 0, tint: .purple) }
}

@Test func scoreRingDefaultSizeIs44() {
    #expect(ScoreRing.defaultSize == 44)
}
