import Testing
@testable import JIDesign

// Non-isolated on purpose: JIHaptic.feedback(for:) is pure, side-effect-free
// mapping logic (no MainActor state), matching the `nonisolated` pure-math
// convention used by GaugeMathTests for JIDesign's MainActor-default package.

@Test func pressInMapsToSelectionFeedback() {
    #expect(JIHaptic.feedback(for: .pressIn) == .selection)
}

@Test func successAndWarningMapToTheirNamedFeedback() {
    #expect(JIHaptic.feedback(for: .success) == .success)
    #expect(JIHaptic.feedback(for: .warning) == .warning)
}

@Test func toggleOnAndOffMapToDistinctImpactFeedback() {
    // Distinct so a toggle's two directions are perceptibly different, not the same buzz twice.
    #expect(JIHaptic.feedback(for: .toggleOn) != JIHaptic.feedback(for: .toggleOff))
}

@Test func everyLadderEventHasAMapping() {
    // Exhaustiveness: every JIHapticEvent case resolves to some SensoryFeedback
    // without a `default:` catch-all silently absorbing a future case.
    for event in JIHapticEvent.allCases {
        _ = JIHaptic.feedback(for: event)
    }
    #expect(JIHapticEvent.allCases.count == 5)
}
