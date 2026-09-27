import SwiftUI

/// W-GUI F2 — report §4.1/4.2: the pure part of the depth recipe, resolved from the level and
/// the accessibility environment so tests can pin it without rendering. `nonisolated`: values.
public nonisolated struct JISurfaceRecipe: Sendable, Equatable {
    /// `.ultraThinMaterial` under the fill (level 1 only, never under Reduce Transparency).
    public var material: Bool
    /// White (dark) / white-60 % (light) fill opacity over the material or the opaque fallback.
    public var fillOpacity: Double
    /// Top-lit highlight: white at 0 → 0 at 38 %.
    public var highlightOpacity: Double
    /// Rim gradient top / mid / bottom opacities (uniform under Increase Contrast).
    public var rimTop: Double, rimMid: Double, rimBottom: Double
    public var rimWidth: CGFloat
    /// Drop shadow (level 1 only).
    public var shadowOpacity: Double, shadowRadius: CGFloat, shadowY: CGFloat
    /// Bottom hairline (black 40 %, level 1 only).
    public var hairlineOpacity: Double
    /// Opaque `secondarySystemGroupedBackground` behind everything (RT, or any nested level).
    public var opaque: Bool
    /// Rims are black in light mode, white in dark.
    public var rimIsDark: Bool

    public static func resolve(level: Int, reduceTransparency: Bool, increasedContrast: Bool, colorScheme: ColorScheme) -> JISurfaceRecipe {
        let light = colorScheme == .light
        let top = level <= 1
        var r = JISurfaceRecipe(
            material: top && !reduceTransparency,
            fillOpacity: light ? 0.60 : (top ? 0.055 : 0.045),
            highlightOpacity: top ? 0.07 : 0.08,
            rimTop: light ? 0.08 : (top ? 0.22 : 0.05),
            rimMid: light ? 0.05 : (top ? 0.05 : 0.05),
            rimBottom: light ? 0.03 : (top ? 0.03 : 0.05),
            rimWidth: 1,
            shadowOpacity: top ? 0.55 : 0, shadowRadius: 14, shadowY: 10,
            hairlineOpacity: top ? 0.40 : 0,
            opaque: reduceTransparency || !top,
            rimIsDark: light)
        if increasedContrast {
            r.rimWidth = 1.5
            let uniform = light ? 0.35 : 0.35
            r.rimTop = uniform; r.rimMid = uniform; r.rimBottom = uniform
        }
        return r
    }
}

/// The card (B-33 §2 → W-GUI F2 report §4.1): a top-lit, rimmed, shadowed surface. Level 1 is
/// the content-layer material card, level 2 the opaque nested tile (no glass on glass), level 3
/// the control fill. The radius comes from the level, never the caller. `tint` is the ONE hero
/// card per screen (16 % → 3 % of the verdict / metric colour, top to bottom). Reduce
/// Transparency → opaque cards (E10); Increase Contrast → uniform 1.5 pt rim (E2).
public extension EnvironmentValues {
    /// W-GUI F2/F10: the system `accessibilityReduceTransparency` / `colorSchemeContrast` keys
    /// are read-only, so the gallery segments and the render tests force the fallbacks through
    /// these overrides. `nil` = follow the system setting.
    @Entry var jiReduceTransparencyOverride: Bool? = nil
    @Entry var jiIncreaseContrastOverride: Bool? = nil
}

public extension View {
    /// Force the Reduce Transparency / Increase Contrast surface fallbacks for a subtree.
    func jiAccessibilityOverrides(reduceTransparency: Bool? = nil, increaseContrast: Bool? = nil) -> some View {
        environment(\.jiReduceTransparencyOverride, reduceTransparency)
            .environment(\.jiIncreaseContrastOverride, increaseContrast)
    }
}

public struct Surface<Content: View>: View {
    private let level: Int, padding: CGFloat, tint: Color?, content: Content
    @Environment(\.jiTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.jiReduceTransparencyOverride) private var rtOverride
    @Environment(\.jiIncreaseContrastOverride) private var icOverride
    public init(level: Int = 1, padding: CGFloat = 16, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.level = level; self.padding = padding; self.tint = tint; self.content = content()
    }
    private var style: (fill: JIColorRole, radius: JIRadiusRole, material: Bool) { surfaceStyle(level: level, theme: theme) }
    private var cornerRadius: CGFloat { theme.radius(style.radius) }
    private var recipe: JISurfaceRecipe {
        JISurfaceRecipe.resolve(level: level,
                                reduceTransparency: rtOverride ?? reduceTransparency,
                                increasedContrast: icOverride ?? (contrast == .increased),
                                colorScheme: colorScheme)
    }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    public var body: some View {
        let r = recipe
        content.padding(padding)
            .background { fill(r).clipShape(shape) }
            .overlay { shape.strokeBorder(rim(r), lineWidth: r.rimWidth) }
            .shadow(color: .black.opacity(r.hairlineOpacity), radius: 0, y: 1)
            .shadow(color: .black.opacity(r.shadowOpacity), radius: r.shadowRadius, y: r.shadowY)
    }

    @ViewBuilder private func fill(_ r: JISurfaceRecipe) -> some View {
        ZStack {
            if level >= 3 {
                theme.color(.control)
            } else if r.opaque {
                theme.color(level <= 1 ? .surface : .surface2)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            if level < 3 {
                Color.white.opacity(r.opaque && !r.rimIsDark ? 0 : r.fillOpacity)
                if let tint {
                    LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
                }
                LinearGradient(stops: [.init(color: .white.opacity(r.highlightOpacity), location: 0),
                                       .init(color: .white.opacity(r.highlightOpacity * 0.3), location: 0.38),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func rim(_ r: JISurfaceRecipe) -> LinearGradient {
        let base: Color = r.rimIsDark ? .black : .white
        return LinearGradient(stops: [.init(color: base.opacity(r.rimTop), location: 0),
                                      .init(color: base.opacity(r.rimMid), location: 0.55),
                                      .init(color: base.opacity(r.rimBottom), location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }
}
