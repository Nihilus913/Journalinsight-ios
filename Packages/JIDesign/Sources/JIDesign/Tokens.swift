import SwiftUI
import JICore
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public extension Color {
    nonisolated init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }

    /// A colour that resolves to `dark` or `light` from the live `colorScheme` (W5a-L1): the
    /// platform's dynamic-colour provider on iOS/macOS, so `.preferredColorScheme` (or the system
    /// appearance) switches every `JIColor` call site with no per-view work. watchOS is always dark.
    nonisolated init(dark: UInt32, light: UInt32, opacity: Double = 1) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(hex: light, alpha: opacity) : UIColor(hex: dark, alpha: opacity)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? NSColor(hex: light, alpha: opacity) : NSColor(hex: dark, alpha: opacity)
        })
        #else
        self.init(hex: dark)
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
private extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}
#elseif os(macOS)
private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}
#endif

/// tokens.ts `ThemeScheme` — which neutral ramp resolves. `nonisolated`: pure value, usable from
/// nonisolated lanes/tests (JIDesign's default isolation is MainActor).
public nonisolated enum JIScheme: String, Sendable, CaseIterable, Codable, Equatable {
    case dark, light
}

/// Verbatim `THEMES[scheme]` from mobile/src/theme/tokens.ts (E13-8, D1-D1 depth ramp): the
/// NEUTRAL ramp only. Verdict colours are never re-derived per scheme (one hex, one meaning).
/// Hairlines are white (dark) / black (light) at the stated opacity — `rgba(255,255,255,0.06)`
/// vs `rgba(0,0,0,0.06)` in the oracle.
public nonisolated struct JIPalette: Sendable, Equatable {
    public let bg: UInt32, surface: UInt32, surface2: UInt32, text: UInt32, muted: UInt32
    public let surface3: UInt32, nested: UInt32, control: UInt32, mutedNested: UInt32
    public let hairlineOuterOpacity: Double, hairlineNestedOpacity: Double

    public static let dark = JIPalette(
        bg: 0x0b0f14, surface: 0x141a22, surface2: 0x1c242e, text: 0xe6edf3, muted: 0x8b98a5,
        surface3: 0x273040, nested: 0x333e4d, control: 0x3f4b5c, mutedNested: 0xb0bcca,
        hairlineOuterOpacity: 0.06, hairlineNestedOpacity: 0.10
    )
    public static let light = JIPalette(
        bg: 0xf4f6f8, surface: 0xffffff, surface2: 0xe7ebf0, text: 0x12161c, muted: 0x5b6672,
        surface3: 0xbad1e9, nested: 0xa9bdd3, control: 0x98abbf, mutedNested: 0x2b3138,
        hairlineOuterOpacity: 0.06, hairlineNestedOpacity: 0.10
    )

    public static func palette(for scheme: JIScheme) -> JIPalette {
        switch scheme { case .dark: dark; case .light: light }
    }
}

/// Verbatim from mobile/src/theme/tokens.ts. Neutrals (`bg`…`mutedNested`, hairlines) are dynamic
/// since W5a-L1: they resolve to `JIPalette.dark`/`.light` from the live `colorScheme`, which the
/// app drives from `ThemePrefs.mode` (`.preferredColorScheme`). Verdict colours stay fixed.
public enum JIColor {
    private static func neutral(_ key: KeyPath<JIPalette, UInt32>) -> Color {
        Color(dark: JIPalette.dark[keyPath: key], light: JIPalette.light[keyPath: key])
    }

    public static let bg = neutral(\.bg)
    public static let surface = neutral(\.surface)
    public static let surface2 = neutral(\.surface2)
    public static let surface3 = neutral(\.surface3)
    public static let nested = neutral(\.nested)
    public static let control = neutral(\.control)
    public static let text = neutral(\.text)
    public static let muted = neutral(\.muted)
    public static let mutedNested = neutral(\.mutedNested)
    /// tokens.ts `hairlineOuter` / `hairlineNested`: white on dark, black on light.
    public static let hairlineOuter = Color(dark: 0xffffff, light: 0x000000, opacity: JIPalette.dark.hairlineOuterOpacity)
    public static let hairlineNested = Color(dark: 0xffffff, light: 0x000000, opacity: JIPalette.dark.hairlineNestedOpacity)
    // Reserved: verdict / band / 0–100 score / status ONLY. Selection + CTA = info.
    public static let go = Color(hex: 0x4ade80)
    public static let reduced = Color(hex: 0xfbbf24)
    public static let danger = Color(hex: 0xf87171)
    public static let info = Color(hex: 0x38bdf8)
    public static let sleep = Color(hex: 0xa78bfa)

    public static func color(for tone: VerdictTone) -> Color {
        switch tone { case .go: go; case .amber: reduced; case .red: danger; case .muted: muted }
    }

    /// A named neutral for an EXPLICIT scheme — does not follow the live `colorScheme`. For
    /// swatches / previews that show "what light would look like" while the app is dark.
    public static func fixed(_ key: KeyPath<JIPalette, UInt32>, for scheme: JIScheme) -> Color {
        Color(hex: JIPalette.palette(for: scheme)[keyPath: key])
    }

    /// B-33 §8.0: the classic value for a role — `JITheme.classic.color(_:)` reads this so the
    /// old language is byte-identical to the statics above.
    public static func classic(_ role: JIColorRole) -> Color {
        switch role {
        case .bg: bg; case .surface: surface; case .surface2: surface2; case .surface3: surface3
        case .nested: nested; case .control: control
        case .text: text; case .muted: muted; case .mutedNested: mutedNested
        case .hairlineOuter: hairlineOuter; case .hairlineNested: hairlineNested
        case .go: go; case .reduced: reduced; case .danger: danger; case .info: info; case .sleep: sleep
        }
    }
}

public enum JIRadius { public static let card: CGFloat = 16; public static let hero: CGFloat = 24 }
