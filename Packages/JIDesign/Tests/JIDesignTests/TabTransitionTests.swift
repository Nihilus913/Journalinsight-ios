import Testing
@testable import JIDesign

// Non-isolated on purpose: tabCrossfadeOpacity / tabCrossfadeIntermediateFrameCount
// are declared `nonisolated` pure math in TabTransition.swift, same convention as
// GaugeMathTests for this MainActor-default package.

@Test func endpointsAreFullyHiddenAndFullyShown() {
    #expect(tabCrossfadeOpacity(progress: 0, forIncoming: true) == 0)
    #expect(tabCrossfadeOpacity(progress: 1, forIncoming: true) == 1)
}

@Test func outgoingLayerIsTheMirrorOfIncoming() {
    for p in stride(from: 0.0, through: 1.0, by: 0.25) {
        #expect(tabCrossfadeOpacity(progress: p, forIncoming: false) == 1 - tabCrossfadeOpacity(progress: p, forIncoming: true))
    }
}

@Test func progressIsClampedOutsideZeroToOne() {
    #expect(tabCrossfadeOpacity(progress: -0.5, forIncoming: true) == 0)
    #expect(tabCrossfadeOpacity(progress: 1.5, forIncoming: true) == 1)
}

// The acceptance criterion: the crossfade must show >=3 intermediate frames,
// proving this is a real animation and not the W1 instant hard-cut.
@Test func transitionShowsAtLeastThreeIntermediateFrames() {
    #expect(tabCrossfadeIntermediateFrameCount(samples: 5) >= 3)
}

@Test func aHardCutWouldShowZeroIntermediateFrames() {
    // Sanity check on the counting method itself: sampling only the two endpoints
    // (a hard cut) must report zero intermediate frames.
    #expect(tabCrossfadeIntermediateFrameCount(samples: 2) == 0)
}
