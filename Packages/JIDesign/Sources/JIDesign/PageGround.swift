import SwiftUI

/// W-GUI F3 — report §4.1 layer 1: the page ground. Not `#000`: a translucent card needs
/// something behind it to be translucent *to*. Dark = `#0B0D11` under a vertical gradient
/// `#0E1015 → #0B0D11 → #090A0D`, a radial accent glow (10 %) top-left and a faint sleep-blue
/// glow (7 %) right. Light = `systemGroupedBackground` + accent glow 6 %. Ignores the safe
/// area: it is the shell's background, never a card's.
public struct JIPageGround: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.jiTheme) private var theme
    private let accent = JIAccent.shared

    public init() {}

    /// The gradient stops of the dark ground (§4.1), top to bottom.
    public nonisolated static let darkStops: [Color] = [
        Color(red: 0.055, green: 0.063, blue: 0.082),   // #0E1015
        Color(red: 0.043, green: 0.051, blue: 0.067),   // #0B0D11
        Color(red: 0.035, green: 0.039, blue: 0.051),   // #090A0D
    ]
    public nonisolated static let darkBase = Color(red: 0.043, green: 0.051, blue: 0.067)   // #0B0D11
    public nonisolated static let accentGlowOpacity: Double = 0.10
    public nonisolated static let accentGlowOpacityLight: Double = 0.06
    public nonisolated static let sleepGlowOpacity: Double = 0.07

    public var body: some View {
        ZStack {
            if colorScheme == .dark {
                Self.darkBase
                LinearGradient(colors: Self.darkStops, startPoint: .top, endPoint: .bottom)
            } else {
                theme.color(.bg)
            }
            RadialGradient(colors: [accent.color.opacity(colorScheme == .dark ? Self.accentGlowOpacity : Self.accentGlowOpacityLight), .clear],
                           center: .init(x: 0.18, y: -0.06), startRadius: 0, endRadius: 420)
            if colorScheme == .dark {
                RadialGradient(colors: [theme.color(.sleep).opacity(Self.sleepGlowOpacity), .clear],
                               center: .init(x: 1.1, y: 0.22), startRadius: 0, endRadius: 360)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

public extension View {
    /// The page ground behind a screen or the tab shell (F3).
    func jiPageGround() -> some View { background(JIPageGround()) }

    /// The same ground as a sheet's presentation background — every sheet step uses it, so a
    /// sheet's cards are translucent to the same ground as the page (F3).
    func jiSheetGround() -> some View { presentationBackground { JIPageGround() } }
}
