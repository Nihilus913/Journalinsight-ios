import SwiftUI
import Testing
@testable import JIDesign

// B-33 §3: text tokens map onto SF text styles; numerals stay SF Rounded + tabular.
@Test(arguments: [
    (JITypography.Token.micro, Font.TextStyle.caption2), (.caption, .caption),
    (.label, .footnote), (.footnote, .footnote),
    (.bodySmall, .subheadline), (.subheadline, .subheadline),
    (.body, .body), (.title, .title2), (.statValue, .headline),
])
func nativeTextStyleMatchesSpec(token: JITypography.Token, style: Font.TextStyle) {
    #expect(JITypography.nativeTextStyle(token) == style)
}

@Test func nativeNumeralWeightsSplitAt40pt() {
    #expect(JITypography.nativeWeight(.numeralCompact) == .semibold)
    #expect(JITypography.nativeWeight(.numeralMedium) == .semibold)
    #expect(JITypography.nativeWeight(.numeralLarge) == .bold)
    #expect(JITypography.nativeWeight(.numeralHero) == .bold)
    #expect(JITypography.nativeWeight(.title) == .bold)
    #expect(JITypography.nativeWeight(.body) == .regular)
}
