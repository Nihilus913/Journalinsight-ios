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
        (.info, .systemBlue),
        (.sleep, .systemPurple),
    ])
    func nativeRoleIsTheSystemSemanticColour(role: JIColorRole, expected: UIColor) {
        #expect(JITheme.native.color(role) == Color(uiColor: expected))
    }
    #endif

    #if os(macOS)
    @Test func nativeBackgroundIsTheSystemSemanticOnMac() {
        #expect(rgb(JITheme.native.color(.bg), .dark) == rgb(Color(nsColor: .windowBackgroundColor), .dark))
    }
    #endif
}
