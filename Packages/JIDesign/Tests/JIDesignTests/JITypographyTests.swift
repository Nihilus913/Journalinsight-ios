import SwiftUI
import Testing
@testable import JIDesign

// W8-L3 — JITypography is `nonisolated`; these run off the main actor on purpose.

@Test func numeralLineHeightMatchesTokensTs() {
    // tokens.ts: numeralLineHeight(fontSize) = Math.ceil(fontSize * 1.25)
    #expect(JITypography.numeralLineHeightRatio == 1.25)
    #expect(JITypography.numeralLineHeight(52) == 65)   // 65.0 exact
    #expect(JITypography.numeralLineHeight(58) == 73)   // 72.5 → ceil 73
    #expect(JITypography.numeralLineHeight(40) == 50)
    #expect(JITypography.numeralLineHeight(28) == 35)
    #expect(JITypography.numeralLineHeight(10.5) == 14) // 13.125 → 14
    #expect(JITypography.numeralLineHeight(.numeralHero) == 65)
}

@Test func tokenSizesAreTheRetrofittedDesignSizes() {
    #expect(JITypography.size(.micro) == 10.5)
    #expect(JITypography.size(.caption) == 11)
    #expect(JITypography.size(.label) == 12)
    #expect(JITypography.size(.bodySmall) == 12.5)
    #expect(JITypography.size(.footnote) == 13)
    #expect(JITypography.size(.body) == 14)
    #expect(JITypography.size(.subheadline) == 15)
    #expect(JITypography.size(.statValue) == 18)
    #expect(JITypography.size(.emoji) == 20)
    #expect(JITypography.size(.cardTitle) == 20)
    #expect(JITypography.size(.cardTitleLarge) == 22)
    #expect(JITypography.size(.numeralSmall) == 22)
    #expect(JITypography.size(.numeralCompact) == 24)
    #expect(JITypography.size(.title) == 26)
    #expect(JITypography.size(.numeralMedium) == 28)
    #expect(JITypography.size(.numeralLarge) == 40)
    #expect(JITypography.size(.numeralGauge) == 44)
    #expect(JITypography.size(.numeralHero) == 52)
    #expect(JITypography.size(.numeralDisplay) == 58)
}

@Test func scaleIsMonotonicInTokenOrder() {
    let sizes = JITypography.Token.allCases.map(JITypography.size)
    #expect(sizes == sizes.sorted())
    // B-47: a design size may now be shared by a text and a numeral token (`.cardTitle` 20 sits
    // with `.emoji`, `.cardTitleLarge` 22 with `.numeralSmall`) — they ride different curves, so
    // the scale stays ordered without being injective. Duplicates are allowed in PAIRS only:
    // three tokens at one size would mean a token nobody can tell apart from its neighbours.
    for size in Set(sizes) {
        #expect(sizes.filter { $0 == size }.count <= 2, "more than two tokens share \(size) pt")
    }
}

@Test func everyTokenAnchorsToAnAppleTextStyle() {
    // Each token declares a Dynamic Type curve; the anchor never scales the design size away from
    // its neighbourhood (a caption-sized token must not ride the largeTitle curve and vice versa).
    for token in JITypography.Token.allCases {
        let style = JITypography.textStyle(token)
        let size = JITypography.size(token)
        switch style {
        case .largeTitle: #expect(size >= 34)
        case .title: #expect(size >= 20 && size < 34)
        case .headline, .title3: #expect(size >= 17 && size < 26)
        case .title2: #expect(size >= 20 && size < 28)
        case .subheadline: #expect(size >= 14 && size < 17)
        case .footnote: #expect(size >= 13 && size < 14)
        case .caption: #expect(size >= 12 && size < 13)
        case .caption2: #expect(size < 12)
        default: Issue.record("unexpected text style \(style) for \(token)")
        }
    }
}

@Test func numeralTokensAreExactlyTheSevenNumerals() {
    let numerals = JITypography.Token.allCases.filter(\.isNumeral)
    #expect(numerals == [.numeralSmall, .numeralCompact, .numeralMedium, .numeralLarge, .numeralGauge, .numeralHero, .numeralDisplay])
    for t in numerals { #expect(JITypography.defaultWeight(t) == .bold) }
    for t in JITypography.Token.allCases where !t.isNumeral && !t.isCardTitle { #expect(JITypography.defaultWeight(t) == .regular) }
    // B-47: a card title is bold in BOTH paths — it is the one text class that carries weight.
    for t in JITypography.Token.allCases where t.isCardTitle {
        #expect(JITypography.defaultWeight(t) == .bold)
        #expect(JITypography.nativeWeight(t) == .bold)
    }
}

@Test func fontBuildsForEveryToken() {
    // Smoke: the Font builder accepts every token at the design size (numerals rounded+tabular,
    // text honours the caller's design).
    for token in JITypography.Token.allCases {
        _ = JITypography.font(token, scaledSize: JITypography.size(token), weight: .semibold)
    }
    #expect(JITypography.font(.footnote, scaledSize: 13, weight: .regular) == Font.system(size: 13, weight: .regular, design: .default))
    #expect(JITypography.font(.numeralHero, scaledSize: 52, weight: .bold) == Font.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
}
