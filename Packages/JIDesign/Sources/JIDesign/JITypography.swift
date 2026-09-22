import SwiftUI

/// W8-L3 — the type scale. RN (`mobile/src/theme/tokens.ts`) has NO numeric scale: sizes come
/// from tailwind `text-*` classes (`text-xs`=12 … `text-base`=16) and per-site `text-[11px]`
/// style props; `tokens.ts` contributes only the numeral typeface and `numeralLineHeight`. The
/// tokens below are the clusters of the 36 fixed `.font(.system(size:))` sites the W8-L3
/// retrofit replaced (Journal/ carried 18 of them), each anchored `relativeTo:` the closest
/// Apple `Font.TextStyle` so Dynamic Type (up to `.accessibility5`) scales the whole app from
/// one file. `Font.system(size:)` itself never scales — only `Font.custom(_:size:relativeTo:)`
/// does — so views apply a token through `.jiFont(_:)` / `.jiNumeral(_:)`, whose `@ScaledMetric`
/// re-evaluates the point size for the live content size category.
/// `nonisolated`: pure values — JIDesign's default isolation is MainActor and tests read these
/// off the main actor.
public nonisolated enum JITypography {
    /// Named sizes. The raw point value is the RN/W5 design size at the default content size
    /// category (`.large`); `textStyle` is the Dynamic Type curve it follows.
    public enum Token: String, CaseIterable, Sendable, Equatable {
        /// 10.5 pt — chart axis labels, day metrics lines (`text-[10.5px]`).
        case micro
        /// 11 pt — stat captions, disclaimer (`text-[11px]`).
        case caption
        /// 12 pt — section labels, search chips, calendar day numerals (`text-xs`).
        case label
        /// 12.5 pt — entry list date + snippet (`text-[12.5px]`).
        case bodySmall
        /// 13 pt — prompts, empty copy, calendar month (`text-[13px]`).
        case footnote
        /// 14 pt — form body (`text-sm`).
        case body
        /// 15 pt — stat values in cards (`text-[15px]`).
        case subheadline
        /// 18 pt — streak stat values (`text-lg`).
        case statValue
        /// 20 pt — entry-row mood emoji (`text-xl`).
        case emoji
        /// 22 pt — SleepCard duration / score numerals.
        case numeralSmall
        /// 24 pt — StatChip value numeral (Today stat row).
        case numeralCompact
        /// 26 pt — mood picker emoji, MIND headline (`text-[26px]`).
        case title
        /// 28 pt — kcal numeral (MacroSummaryCard).
        case numeralMedium
        /// 40 pt — energy balance / gate-rationale verdict word.
        case numeralLarge
        /// 44 pt — ReadinessArcGauge score numeral.
        case numeralGauge
        /// 52 pt — Today verdict word (VerdictHero).
        case numeralHero
        /// 58 pt — live HR (SessionCoach).
        case numeralDisplay

        /// Numeral tokens render rounded + tabular and carry the RN line-height floor.
        public var isNumeral: Bool {
            switch self {
            case .numeralSmall, .numeralCompact, .numeralMedium, .numeralLarge, .numeralGauge, .numeralHero, .numeralDisplay: true
            default: false
            }
        }
    }

    /// Design point size at the default content size category.
    public static func size(_ token: Token) -> CGFloat {
        switch token {
        case .micro: 10.5
        case .caption: 11
        case .label: 12
        case .bodySmall: 12.5
        case .footnote: 13
        case .body: 14
        case .subheadline: 15
        case .statValue: 18
        case .emoji: 20
        case .numeralSmall: 22
        case .numeralCompact: 24
        case .title: 26
        case .numeralMedium: 28
        case .numeralLarge: 40
        case .numeralGauge: 44
        case .numeralHero: 52
        case .numeralDisplay: 58
        }
    }

    /// The Apple text style whose Dynamic Type curve the token follows.
    public static func textStyle(_ token: Token) -> Font.TextStyle {
        switch token {
        case .micro, .caption: .caption2
        case .label, .bodySmall: .caption
        case .footnote: .footnote
        case .body, .subheadline: .subheadline
        case .statValue: .headline
        case .emoji: .title3
        case .numeralSmall, .numeralCompact, .title, .numeralMedium: .title
        case .numeralLarge, .numeralGauge, .numeralHero, .numeralDisplay: .largeTitle
        }
    }

    /// The `Font` for a token at an already-scaled point size (what `.jiFont` feeds after
    /// `@ScaledMetric`). Numeral tokens are rounded + tabular (RN `numeralStyle`: Space Grotesk 700
    /// with `fontVariant: tabular-nums` → SF Rounded here); `design` only applies to text tokens.
    public static func font(_ token: Token, scaledSize: CGFloat, weight: Font.Weight, design: Font.Design = .default) -> Font {
        if token.isNumeral {
            return Font.system(size: scaledSize, weight: weight, design: .rounded).monospacedDigit()
        }
        return Font.system(size: scaledSize, weight: weight, design: design)
    }

    /// Default weight per token: numerals are bold like the oracle's numeral face; text is regular.
    public static func defaultWeight(_ token: Token) -> Font.Weight { token.isNumeral ? .bold : .regular }

    // MARK: B-33 §3 — native language

    /// The SF text style a text token renders as under `.native` (no custom sizes: the system
    /// curve owns the size). Numeral tokens are listed for completeness but never use this —
    /// they keep the sized rounded + tabular path.
    public static func nativeTextStyle(_ token: Token) -> Font.TextStyle {
        switch token {
        case .micro: .caption2
        case .caption: .caption
        case .label, .footnote: .footnote
        case .bodySmall, .subheadline: .subheadline
        case .body: .body
        case .title, .emoji: .title2
        case .statValue: .headline
        case .numeralSmall, .numeralCompact, .numeralMedium, .numeralLarge, .numeralGauge, .numeralHero, .numeralDisplay: .largeTitle
        }
    }

    /// Native weights: numerals semibold below 40 pt, bold from 40 pt; titles bold; text regular.
    public static func nativeWeight(_ token: Token) -> Font.Weight {
        if token.isNumeral { return size(token) >= 40 ? .bold : .semibold }
        return token == .title ? .bold : .regular
    }

    // MARK: numeralLineHeight — port of tokens.ts `NUMERAL_LINE_HEIGHT_RATIO` / `numeralLineHeight`

    /// tokens.ts `NUMERAL_LINE_HEIGHT_RATIO` (R2.3 hotfix: the numeral face's ascent/descent run
    /// taller than `fontSize`; an unset/tight line height clipped glyph tops).
    public static let numeralLineHeightRatio: CGFloat = 1.25

    /// tokens.ts `numeralLineHeight(fontSize)` = `Math.ceil(fontSize * 1.25)`. Every numeral site
    /// pairs its font with this as its minimum line box so the glyph tops never clip.
    public static func numeralLineHeight(_ fontSize: CGFloat) -> CGFloat {
        (fontSize * numeralLineHeightRatio).rounded(.up)
    }

    /// Line height for a numeral token at the design size.
    public static func numeralLineHeight(_ token: Token) -> CGFloat {
        numeralLineHeight(size(token))
    }
}

/// Applies a `JITypography` token as a Dynamic-Type-scaled font. `@ScaledMetric(relativeTo:)`
/// is the only system-font route that follows the content size category; for numeral tokens it
/// also feeds the `numeralLineHeight` frame floor (a size that feeds a frame — the card's
/// `@ScaledMetric` case).
public struct JITypographyModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    @Environment(\.jiTheme) private var theme
    private let token: JITypography.Token
    private let explicitWeight: Font.Weight?
    private let design: Font.Design

    public init(token: JITypography.Token, weight: Font.Weight?, design: Font.Design = .default) {
        self.token = token
        self.explicitWeight = weight
        self.design = design
        _scaledSize = ScaledMetric(wrappedValue: JITypography.size(token), relativeTo: JITypography.textStyle(token))
    }

    private var weight: Font.Weight {
        explicitWeight ?? (theme == .native ? JITypography.nativeWeight(token) : JITypography.defaultWeight(token))
    }

    public func body(content: Content) -> some View {
        if theme == .native, !token.isNumeral {
            // §3: text styles only — the system curve owns the size.
            content.font(.system(JITypography.nativeTextStyle(token), design: design, weight: weight))
        } else {
            let font = JITypography.font(token, scaledSize: scaledSize, weight: weight, design: design)
            if token.isNumeral {
                content.font(font).frame(minHeight: JITypography.numeralLineHeight(scaledSize), alignment: .leading)
            } else {
                content.font(font)
            }
        }
    }
}

public extension View {
    /// `.jiFont(.footnote, weight: .semibold)` — a text token, scaled with Dynamic Type.
    func jiFont(_ token: JITypography.Token, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(JITypographyModifier(token: token, weight: weight, design: design))
    }

    /// `.jiNumeral(.numeralHero)` — a numeral token: rounded, tabular, bold by default, with the RN
    /// `numeralLineHeight` floor so glyph tops never clip.
    func jiNumeral(_ token: JITypography.Token, weight: Font.Weight? = nil) -> some View {
        modifier(JITypographyModifier(token: token, weight: weight, design: .rounded))
    }
}
