import SwiftUI
import Testing
@testable import JIDesign

private func rgb(_ color: Color, _ scheme: ColorScheme) -> (Double, Double, Double) {
    var env = EnvironmentValues()
    env.colorScheme = scheme
    let r = color.resolve(in: env)
    return (Double(r.red), Double(r.green), Double(r.blue))
}

@MainActor
struct NativePaletteTests {
    @Test func classicRolesAreTheExistingStatics() {
        // Regression: classic must stay byte-identical (CONTEXT §7 hex table).
        let (r, g, b) = rgb(JITheme.classic.color(.bg), .dark)
        #expect(abs(r - 11.0 / 255) < 0.002 && abs(g - 15.0 / 255) < 0.002 && abs(b - 20.0 / 255) < 0.002)
        #expect(JITheme.classic.color(.go) == JIColor.go)
        #expect(JITheme.classic.color(.hairlineOuter) == JIColor.hairlineOuter)
    }

    @Test func nativeNeutralsAreDynamic() {
        // System-semantic colours differ between light and dark; a hex would not.
        let dark = rgb(JITheme.native.color(.text), .dark)
        let light = rgb(JITheme.native.color(.text), .light)
        #expect(dark != light)
    }

    @Test func nativeBackgroundIsNotTheClassicHex() {
        #expect(rgb(JITheme.native.color(.bg), .dark) != rgb(JITheme.classic.color(.bg), .dark))
    }

    @Test func everyRoleResolvesInBothThemes() {
        for theme in JITheme.allCases {
            for role in JIColorRole.allCases {
                _ = rgb(theme.color(role), .dark)
                _ = rgb(theme.color(role), .light)
            }
        }
    }

    #if os(macOS)
    @Test func nativeBackgroundIsTheSystemSemanticOnMac() {
        #expect(rgb(JITheme.native.color(.bg), .dark) == rgb(Color(nsColor: .windowBackgroundColor), .dark))
    }
    #endif
}
