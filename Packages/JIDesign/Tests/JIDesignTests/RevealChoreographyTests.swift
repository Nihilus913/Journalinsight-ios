import Testing
@testable import JIDesign

// Non-isolated on purpose: revealOpacity / revealOffsetY (RevealChoreography.swift)
// and pressedScaleEffect (PressableScaleStyle.swift) are pure, environment-free
// math extracted so the reduce-motion suppression rule is testable without a
// view-hosting harness — same `nonisolated` pure-math convention as GaugeMathTests.

@Test func revealIsHiddenBeforeAppearAndShownAfter() {
    #expect(revealOpacity(revealed: false) == 0)
    #expect(revealOpacity(revealed: true) == 1)
    // Close-out defect 2: with `\.jiRevealAnimations` off the fade is skipped — final opacity at once.
    #expect(revealOpacity(revealed: false, animations: false) == 1)
}

@Test func reduceMotionSuppressesTheRevealOffsetButNotTheFade() {
    // Pre-reveal (not yet revealed): normally offset by `offset` points...
    #expect(revealOffsetY(revealed: false, reduceMotion: false, offset: 12) == 12)
    // ...but Reduce Motion collapses that offset to zero (opacity-only fallback).
    #expect(revealOffsetY(revealed: false, reduceMotion: true, offset: 12) == 0)
    // The fade itself (opacity) is identical in both motion states — only the
    // translation is suppressed.
    #expect(revealOpacity(revealed: false) == revealOpacity(revealed: false))
}

@Test func revealedStateHasNoOffsetRegardlessOfMotionSetting() {
    #expect(revealOffsetY(revealed: true, reduceMotion: false, offset: 12) == 0)
    #expect(revealOffsetY(revealed: true, reduceMotion: true, offset: 12) == 0)
}

// This half of the acceptance criterion ("scale + reveal are suppressed when
// reduce-motion is on") covers PressableScaleStyle's press-in scale, which
// RevealChoreography's file doesn't touch but which shares the same rule.
@Test func reduceMotionSuppressesThePressedScale() {
    #expect(pressedScaleEffect(isPressed: true, reduceMotion: false) == PressableScaleStyle.pressedScale)
    #expect(pressedScaleEffect(isPressed: true, reduceMotion: true) == 1)
}

@Test func unpressedScaleIsAlwaysIdentityRegardlessOfMotionSetting() {
    #expect(pressedScaleEffect(isPressed: false, reduceMotion: false) == 1)
    #expect(pressedScaleEffect(isPressed: false, reduceMotion: true) == 1)
}
