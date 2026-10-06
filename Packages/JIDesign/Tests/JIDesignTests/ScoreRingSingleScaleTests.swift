import SwiftUI
import Testing
@testable import JIDesign

/// W-BUG1 BUG1-7 (RG-21 side finding): a caller that already scales its side with its own
/// `@ScaledMetric` (DecideReadinessRing) hands ScoreRing a scaled size — ScoreRing must not scale
/// it a second time, or the ring grows by the AX factor squared at accessibility sizes.
@Suite @MainActor struct ScoreRingSingleScaleTests {
    private func renderedWidth<V: View>(_ view: V, _ size: DynamicTypeSize) -> CGFloat {
        let renderer = ImageRenderer(content: view.jiRevealAnimations(false).environment(\.dynamicTypeSize, size))
        renderer.scale = 1
        return renderer.cgImage.map { CGFloat($0.width) } ?? -1
    }

    @Test func preScaledSideIsNotScaledAgainAtAX3() {
        let ring = ScoreRing(value: 72, max: 100, tint: .blue, size: 64, scalesWithText: false)
        #expect(renderedWidth(ring, .accessibility3) == 64)
        #expect(renderedWidth(ring, .large) == 64)
    }

    @Test func defaultRingStillScalesWithText() {
        let ring = ScoreRing(value: 72, max: 100, tint: .blue, size: 64)
        #expect(renderedWidth(ring, .large) == 64)
        #if os(iOS)
        // ScaledMetric only scales on iOS (macOS `swift test` renders every size at 64).
        #expect(renderedWidth(ring, .accessibility3) > 64)
        #endif
    }
}
