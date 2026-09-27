import SwiftUI
import Testing
@testable import JIDesign
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

private func rgb(_ color: Color, _ scheme: ColorScheme) -> (Double, Double, Double) {
    var env = EnvironmentValues()
    env.colorScheme = scheme
    let r = color.resolve(in: env)
    return (Double(r.red), Double(r.green), Double(r.blue))
}

@MainActor
struct NativePaletteTests {
    @Test func nativeNeutralsAreDynamic() {
        // System-semantic colours differ between light and dark; a hex would not.
        let dark = rgb(JITheme.native.color(.text), .dark)
        let light = rgb(JITheme.native.color(.text), .light)
        #expect(dark != light)
    }

    @Test func everyRoleResolvesInBothSchemes() {
        for theme in JITheme.allCases {
            for role in JIColorRole.allCases {
                _ = rgb(theme.color(role), .dark)
                _ = rgb(theme.color(role), .light)
            }
        }
    }

    /// Spec §6 — semantic identity, not a hex table: each role IS the platform's semantic colour,
    /// so it keeps following the system (light/dark, increased contrast, future OS tweaks).
    #if os(iOS) || os(tvOS) || os(visionOS)
    @Test(arguments: [
        (JIColorRole.bg, UIColor.systemGroupedBackground),
        (.surface, .secondarySystemGroupedBackground),
        (.surface2, .tertiarySystemGroupedBackground),
        (.text, .label),
        (.muted, .secondaryLabel),
        (.mutedNested, .tertiaryLabel),
        (.hairlineOuter, .separator),
        (.go, .systemGreen),
        (.reduced, .systemOrange),
        (.danger, .systemRed),
        (.kcal, .systemOrange),
        (.protein, .systemPink),
        (.carbs, .systemYellow),
        (.fat, .systemCyan),
    ])
    func nativeRoleIsTheSystemSemanticColour(role: JIColorRole, expected: UIColor) {
        #expect(JITheme.native.color(role) == Color(uiColor: expected))
    }

    /// W-GUI F4 made HRV / Sleep dynamic (the report's dark hexes; the system tint in light), so
    /// they are compared by the colour the light scheme resolves to (W-B57-W5 fixer).
    @Test(arguments: [(JIColorRole.hrv, UIColor.systemBlue), (.sleep, .systemPurple)])
    func metricRoleIsTheSystemTintInLight(role: JIColorRole, expected: UIColor) {
        let light = UITraitCollection(userInterfaceStyle: .light)
        #expect(UIColor(JITheme.native.color(role)).resolvedColor(with: light) == expected.resolvedColor(with: light))
    }
    #endif

    #if os(macOS)
    @Test func nativeBackgroundIsTheSystemSemanticOnMac() {
        #expect(rgb(JITheme.native.color(.bg), .dark) == rgb(Color(nsColor: .windowBackgroundColor), .dark))
    }
    #endif
}

// W-GUI F4 — report §4.3 contrast table: body ≥ 4.5:1 on the dark card (#1A1C21).
private func luminance(_ c: (Double, Double, Double)) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
}

@MainActor
@Test(arguments: [JIColorRole.hrv, .rhr, .load, .sleep, .kcal, .protein, .carbs, .fat, .text, .muted])
func darkMetricRolesReadOnTheCard(role: JIColorRole) {
    let card = luminance((0x1A / 255.0, 0x1C / 255.0, 0x21 / 255.0))
    let fg = luminance(JINativePalette.darkHex[role].map { (Double($0.0) / 255, Double($0.1) / 255, Double($0.2) / 255) }
                       ?? rgb(JITheme.native.color(role), .dark))
    let ratio = (max(fg, card) + 0.05) / (min(fg, card) + 0.05)
    #expect(ratio >= 4.5, "\(role) \(ratio)")
}

@MainActor
@Test func newRolesAreNotTheVerdictOrAccentColours() {
    let rhr = rgb(JITheme.native.color(.rhr), .dark)
    let load = rgb(JITheme.native.color(.load), .dark)
    for verdict in [JIColorRole.go, .reduced, .danger, .info] {
        let v = rgb(JITheme.native.color(verdict), .dark)
        #expect(rhr != v && load != v)
    }
    #expect(rgb(JITheme.native.color(.steps), .dark) == rgb(JITheme.native.color(.text), .dark))
    #expect(JINativePalette.darkHex[.hrv]! == (0x6F, 0xA8, 0xFF))
    #expect(JINativePalette.darkHex[.rhr]! == (0xFF, 0x9F, 0x8A))
    #expect(JINativePalette.darkHex[.load]! == (0xC8, 0xA2, 0xFF))
    #expect(JINativePalette.darkHex[.sleep]! == (0x8F, 0xA8, 0xFF))
}
