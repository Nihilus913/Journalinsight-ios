import SwiftUI
import Testing
@testable import JIDesign

// W5a-L1 (P-appearance). The light scheme is verbatim `THEMES.light` from
// mobile/src/theme/tokens.ts (E13-8); `JIColor` neutrals are now dynamic colours that resolve
// per `colorScheme`, so every pre-existing `JIColor.bg` call site follows the mode switch with no
// edit. Verdict colours are NOT re-derived per scheme (one hex, one meaning — tokens.ts).

private func components(_ color: Color, _ scheme: ColorScheme) -> (r: Double, g: Double, b: Double, a: Double) {
    var env = EnvironmentValues()
    env.colorScheme = scheme
    let r = color.resolve(in: env)
    return (Double(r.red), Double(r.green), Double(r.blue), Double(r.opacity))
}

private func expectHex(_ color: Color, _ scheme: ColorScheme, _ hex: UInt32, _ what: Comment) {
    let c = components(color, scheme)
    #expect(abs(c.r - Double((hex >> 16) & 0xff) / 255) < 0.002, what)
    #expect(abs(c.g - Double((hex >> 8) & 0xff) / 255) < 0.002, what)
    #expect(abs(c.b - Double(hex & 0xff) / 255) < 0.002, what)
}

@MainActor
struct TokensLightTests {
    /// Exit criterion: "light tokens verbatim from tokens.ts light scheme (test compares ≥ 5 named colours)".
    @Test func lightPaletteIsVerbatimFromTokensTs() {
        let light = JIPalette.light
        #expect(light.bg == 0xf4f6f8)
        #expect(light.surface == 0xffffff)
        #expect(light.surface2 == 0xe7ebf0)
        #expect(light.text == 0x12161c)
        #expect(light.muted == 0x5b6672)
        #expect(light.surface3 == 0xbad1e9)
        #expect(light.nested == 0xa9bdd3)
        #expect(light.control == 0x98abbf)
        #expect(light.mutedNested == 0x2b3138)
        #expect(light.hairlineOuterOpacity == 0.06)
        #expect(light.hairlineNestedOpacity == 0.10)
    }

    @Test func darkPaletteIsUnchanged() {
        let dark = JIPalette.dark
        #expect(dark.bg == 0x0b0f14)
        #expect(dark.surface == 0x141a22)
        #expect(dark.surface2 == 0x1c242e)
        #expect(dark.text == 0xe6edf3)
        #expect(dark.muted == 0x8b98a5)
        #expect(dark.surface3 == 0x273040)
        #expect(dark.nested == 0x333e4d)
        #expect(dark.control == 0x3f4b5c)
        #expect(dark.mutedNested == 0xb0bcca)
        #expect(JIPalette.palette(for: .dark) == dark)
        #expect(JIPalette.palette(for: .light) == JIPalette.light)
    }

    /// The mode switch: the SAME `JIColor.*` value resolves to the light ramp under a light
    /// `colorScheme` and to the dark ramp under a dark one (≥ 5 named colours, both ways).
    @Test func jiColorNeutralsFollowTheColorScheme() {
        let named: [(String, Color, KeyPath<JIPalette, UInt32>)] = [
            ("bg", JIColor.bg, \.bg), ("surface", JIColor.surface, \.surface),
            ("surface2", JIColor.surface2, \.surface2), ("surface3", JIColor.surface3, \.surface3),
            ("nested", JIColor.nested, \.nested), ("control", JIColor.control, \.control),
            ("text", JIColor.text, \.text), ("muted", JIColor.muted, \.muted),
            ("mutedNested", JIColor.mutedNested, \.mutedNested),
        ]
        for (name, color, key) in named {
            expectHex(color, .light, JIPalette.light[keyPath: key], "light \(name)")
            expectHex(color, .dark, JIPalette.dark[keyPath: key], "dark \(name)")
        }
    }

    @Test func hairlinesAreWhiteOnDarkAndBlackOnLight() {
        let dark = components(JIColor.hairlineOuter, .dark)
        #expect(dark.r > 0.99 && abs(dark.a - 0.06) < 0.002)
        let light = components(JIColor.hairlineOuter, .light)
        #expect(light.r < 0.01 && abs(light.a - 0.06) < 0.002)
        #expect(abs(components(JIColor.hairlineNested, .light).a - 0.10) < 0.002)
    }

    /// tokens.ts: "Verdict colors (C.verdict.*) are NOT re-derived per scheme".
    @Test func verdictColoursDoNotSwitchWithScheme() {
        for (color, hex) in [(JIColor.go, 0x4ade80 as UInt32), (JIColor.reduced, 0xfbbf24), (JIColor.danger, 0xf87171), (JIColor.info, 0x38bdf8), (JIColor.sleep, 0xa78bfa)] {
            expectHex(color, .light, hex, "verdict light")
            expectHex(color, .dark, hex, "verdict dark")
        }
    }

    /// `JIColor.fixed(_:for:)` resolves a named neutral for an explicit scheme (previews /
    /// swatches that must NOT follow the live scheme).
    @Test func fixedResolvesForAnExplicitScheme() {
        expectHex(JIColor.fixed(\.bg, for: .light), .dark, 0xf4f6f8, "fixed light bg under dark env")
        expectHex(JIColor.fixed(\.bg, for: .dark), .light, 0x0b0f14, "fixed dark bg under light env")
    }
}
