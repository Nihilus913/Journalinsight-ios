import SwiftUI
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// B-33 §1: the native language resolves neutrals to the platform's semantic colours (dynamic —
/// light/dark and `ThemePrefs.mode` keep working) and verdicts to the system tints.
/// watchOS has no UIKit semantic colours: `label` on black (spec §1), greys hand-picked.
enum JINativePalette {
    /// W-GUI F4 — report §4.3 dark values of the metric roles (light mode keeps system tints).
    /// Pinned here so tests read the hex, not a trait-resolved dynamic colour.
    nonisolated static let darkHex: [JIColorRole: (Int, Int, Int)] = [
        .hrv: (0x6F, 0xA8, 0xFF), .sleep: (0x8F, 0xA8, 0xFF), .rhr: (0xFF, 0x9F, 0x8A), .load: (0xC8, 0xA2, 0xFF),
    ]
    #if os(iOS) || os(tvOS) || os(visionOS)
    /// A dynamic colour: the report's dark hex, the system tint in light mode.
    static func dynamic(dark: (Int, Int, Int), light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: CGFloat(dark.0) / 255, green: CGFloat(dark.1) / 255, blue: CGFloat(dark.2) / 255, alpha: 1)
                : light
        })
    }
    #endif

    static func color(_ role: JIColorRole) -> Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        switch role {
        case .bg: Color(uiColor: .systemGroupedBackground)
        case .surface: Color(uiColor: .secondarySystemGroupedBackground)
        case .surface2: Color(uiColor: .tertiarySystemGroupedBackground)
        case .surface3: Color(uiColor: .quaternarySystemFill)
        case .nested: Color(uiColor: .tertiarySystemFill)
        case .control: Color(uiColor: .secondarySystemFill)
        case .text: Color(uiColor: .label)
        case .muted: Color(uiColor: .secondaryLabel)
        case .mutedNested: Color(uiColor: .tertiaryLabel)
        case .hairlineOuter, .hairlineNested: Color(uiColor: .separator)
        case .go: Color(uiColor: .systemGreen)
        case .reduced: Color(uiColor: .systemOrange)
        case .danger: Color(uiColor: .systemRed)
        case .info: JIAccent.shared.color
        // W-GUI F4 (report §4.3): the dark metric hexes; system tints stay in light mode.
        case .hrv: Self.dynamic(dark: Self.darkHex[.hrv]!, light: .systemBlue)
        case .sleep: Self.dynamic(dark: Self.darkHex[.sleep]!, light: .systemPurple)
        case .rhr: Self.dynamic(dark: Self.darkHex[.rhr]!, light: UIColor(red: 0.80, green: 0.33, blue: 0.24, alpha: 1))
        case .load: Self.dynamic(dark: Self.darkHex[.load]!, light: .systemIndigo)
        case .steps: Color(uiColor: .label)
        case .kcal: Color(uiColor: .systemOrange)
        case .protein: Color(uiColor: .systemPink)
        case .carbs: Color(uiColor: .systemYellow)
        case .fat: Color(uiColor: .systemCyan)
        }
        #elseif os(macOS)
        switch role {
        case .bg: Color(nsColor: .windowBackgroundColor)
        case .surface: Color(nsColor: .controlBackgroundColor)
        case .surface2: Color(nsColor: .underPageBackgroundColor)
        case .surface3: Color(nsColor: .quaternaryLabelColor)
        case .nested: Color(nsColor: .tertiaryLabelColor)
        case .control: Color(nsColor: .secondaryLabelColor)
        case .text: Color(nsColor: .labelColor)
        case .muted: Color(nsColor: .secondaryLabelColor)
        case .mutedNested: Color(nsColor: .tertiaryLabelColor)
        case .hairlineOuter, .hairlineNested: Color(nsColor: .separatorColor)
        case .go: Color(nsColor: .systemGreen)
        case .reduced: Color(nsColor: .systemOrange)
        case .danger: Color(nsColor: .systemRed)
        case .info: JIAccent.shared.color
        case .hrv: Color(nsColor: .systemBlue)
        case .sleep: Color(nsColor: .systemPurple)
        case .rhr: Color(red: 1.0, green: 0.62, blue: 0.54)
        case .load: Color(red: 0.78, green: 0.64, blue: 1.0)
        case .steps: Color(nsColor: .labelColor)
        case .kcal: Color(nsColor: .systemOrange)
        case .protein: Color(nsColor: .systemPink)
        case .carbs: Color(nsColor: .systemYellow)
        case .fat: Color(nsColor: .systemCyan)
        }
        #else
        switch role {
        case .bg: .black
        case .surface: Color(white: 0.11)
        case .surface2: Color(white: 0.17)
        case .surface3: Color(white: 0.22)
        case .nested: Color(white: 0.27)
        case .control: Color(white: 0.33)
        case .text: .primary
        case .muted: .secondary
        case .mutedNested: Color(white: 0.55)
        case .hairlineOuter, .hairlineNested: Color(white: 1, opacity: 0.12)
        case .go: .green
        case .reduced: .orange
        case .danger: .red
        case .info: JIAccent.shared.color
        case .hrv: .blue
        case .sleep: .purple
        case .rhr: Color(red: 1.0, green: 0.62, blue: 0.54)
        case .load: Color(red: 0.78, green: 0.64, blue: 1.0)
        case .steps: .primary
        case .kcal: .orange
        case .protein: .pink
        case .carbs: .yellow
        case .fat: .cyan
        }
        #endif
    }
}
