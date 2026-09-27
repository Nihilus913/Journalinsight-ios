import SwiftUI

/// W-GUI F8 — report §4.2 "Rings: `.shadow(color: tint.opacity(0.4), radius: 6)`": the Bevel /
/// WHOOP glow on a ring's value arc. Static (no animation of its own, Reduce Motion safe); off
/// under Increase Contrast, where a soft halo only blurs the edge the setting asks for.
public nonisolated enum JIRingGlow {
    public static let radius: CGFloat = 6
    public static let opacity: Double = 0.4
    public static func radius(increasedContrast: Bool) -> CGFloat { increasedContrast ? 0 : radius }
}

public extension View {
    /// The value arc's glow (F8). Apply to the arc only, never to the track.
    func jiRingGlow(_ tint: Color) -> some View { modifier(JIRingGlowModifier(tint: tint)) }
}

struct JIRingGlowModifier: ViewModifier {
    let tint: Color
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.jiIncreaseContrastOverride) private var icOverride
    func body(content: Content) -> some View {
        content.shadow(color: tint.opacity(JIRingGlow.opacity),
                       radius: JIRingGlow.radius(increasedContrast: icOverride ?? (contrast == .increased)))
    }
}
