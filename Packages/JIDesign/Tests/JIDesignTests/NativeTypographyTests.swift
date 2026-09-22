import SwiftUI
import Testing
@testable import JIDesign

// B-33 §3 + B-47 contract: the WHOLE token → SF-text-style table, text and numerals together.
// This is the table the wave card fixes so L1 and L2 land on the same scale.
@Test(arguments: [
    (JITypography.Token.micro, Font.TextStyle.caption2), (.caption, .caption),
    (.label, .subheadline), (.footnote, .footnote),
    (.bodySmall, .subheadline), (.subheadline, .subheadline),
    (.body, .body), (.cardTitle, .title3), (.cardTitleLarge, .title2),
    (.title, .title2), (.emoji, .title2), (.statValue, .headline),
    (.numeralSmall, .title2), (.numeralCompact, .title), (.numeralMedium, .title),
    (.numeralLarge, .largeTitle), (.numeralGauge, .largeTitle),
    (.numeralHero, .largeTitle), (.numeralDisplay, .largeTitle),
])
func nativeTextStyleMatchesSpec(token: JITypography.Token, style: Font.TextStyle) {
    #expect(JITypography.nativeTextStyle(token) == style)
}

/// Every token is in the table above — a new token must declare its native style, not inherit
/// someone else's by accident.
@Test func theNativeTableCoversEveryToken() {
    for token in JITypography.Token.allCases { _ = JITypography.nativeTextStyle(token) }
    #expect(JITypography.Token.allCases.count == 19)
}

// B-47 root cause: the four context numerals now take the native branch (they scale with Dynamic
// Type off a text style); the three display numerals stay on the sized `@ScaledMetric` path.
@Test func theContextNumeralsTakeTheNativeBranchAndTheDisplayOnesDoNot() {
    #expect(JITypography.Token.allCases.filter(\.usesNativeNumeralStyle)
            == [.numeralSmall, .numeralCompact, .numeralMedium, .numeralLarge])
    for t in [JITypography.Token.numeralGauge, .numeralHero, .numeralDisplay] {
        #expect(!t.usesNativeNumeralStyle)
        #expect(!t.usesNativeTextStyle)
    }
    for t in JITypography.Token.allCases where !t.isNumeral { #expect(t.usesNativeTextStyle) }
}

/// The behaviour the token map exists for. A `Font.system(_ style:)` font is the only
/// system-font route that follows the content size category, so asserting that `.native`
/// resolves each context numeral to a TEXT STYLE (not a pinned size) IS the "numerals scale with
/// Dynamic Type" contract — before B-47 `numeralCompact` was `Font.system(size: 24)` at every
/// setting. (Dynamic Type itself has no effect on the macOS host these tests run on; the
/// rendered ax3/ax5 evidence is the 456-cell simulator sweep.)
@Test func everyScalingNumeralResolvesToATextStyleFontNotAPinnedSize() {
    for token in JITypography.Token.allCases where token.usesNativeNumeralStyle {
        let weight = JITypography.nativeWeight(token)
        let expected = Font.system(JITypography.nativeTextStyle(token), design: .rounded, weight: weight).monospacedDigit()
        #expect(JITypography.nativeFont(token, weight: weight) == expected)
        #expect(JITypography.nativeFont(token, weight: weight)
                != Font.system(size: JITypography.size(token), weight: weight, design: .rounded).monospacedDigit())
    }
}

/// Fitness's context numeral is `.title` (28 pt at the default size), not the old pinned 24, and
/// the card title is `.title3` (20) — the two sizes Toby measured off the reference shots.
@Test func theContractSizesAreTheNativeStylesTheyClaim() {
    #expect(JITypography.nativeTextStyle(.numeralCompact) == .title)       // 28 pt @ .large
    #expect(JITypography.nativeTextStyle(.numeralSmall) == .title2)        // 22 pt
    #expect(JITypography.nativeTextStyle(.numeralLarge) == .largeTitle)    // 34 pt
    #expect(JITypography.nativeTextStyle(.cardTitle) == .title3)           // 20 pt
    #expect(JITypography.nativeTextStyle(.body) == .body)                  // 17 pt
    #expect(JITypography.nativeTextStyle(.subheadline) == .subheadline)    // 15 pt
}

/// The card title and a tinted numeral both render at an accessibility content size (the sweep
/// checks the pixels; this checks `body` does not trap on the way there).
@Test @MainActor func theNewTokensRenderAtAnAccessibilitySize() {
    for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
        let renderer = ImageRenderer(content:
            VStack {
                Text("Steps").jiFont(.cardTitle)
                Text("232").jiNumeral(.numeralCompact, tint: .go)
            }
            .frame(width: 180)
            .jiTheme(.native)
            .environment(\.dynamicTypeSize, size)
        )
        #expect(renderer.cgImage != nil, "new tokens render at \(size)")
    }
}

/// The tint seam: `jiNumeral(_:tint:)` renders (the colour itself is `theme.color(role)`, already
/// covered by `JIThemeTests`); an untinted call must still render for every token.
@Test @MainActor func tintedNumeralsRender() {
    expectRenders("tinted numeral") {
        VStack {
            Text("52").jiNumeral(.numeralCompact, tint: .info)
            Text("ms").jiFont(.subheadline, weight: .semibold, tint: .info)
            Text("Steps").jiFont(.cardTitle)
        }
    }
}

@Test func nativeNumeralWeightsSplitAt40pt() {
    #expect(JITypography.nativeWeight(.numeralCompact) == .semibold)
    #expect(JITypography.nativeWeight(.numeralMedium) == .semibold)
    #expect(JITypography.nativeWeight(.numeralLarge) == .bold)
    #expect(JITypography.nativeWeight(.numeralHero) == .bold)
    #expect(JITypography.nativeWeight(.title) == .bold)
    #expect(JITypography.nativeWeight(.body) == .regular)
}
