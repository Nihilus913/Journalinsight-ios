import SwiftUI
import Testing
@testable import JIFeatures

/// W-FIX3 BUG-33 (R3-13): seven fixed 44-pt day chips cannot hold AX3 numerals — "19 20 21…" ran
/// into each other and the selection rings. The day strip caps its type size (like the Fitness
/// calendar strip); the caption above it still scales.
@Test func trainingDayStripCapsItsTypeSizeBelowAXSizes() {
    #expect(TrainingDayStrip.maxTypeSize == .xxxLarge)
    #expect(!TrainingDayStrip.maxTypeSize.isAccessibilitySize)
}
