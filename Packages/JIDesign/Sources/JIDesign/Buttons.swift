import SwiftUI

/// W-GUI F9 — report §4.5 "Buttons": 52 pt, radius 18. Primary = the accent fill with a BLACK
/// label (W-FIX3 BUG-30 kept: never white on the tint); secondary = the card fill with the rim.
/// One primary per screen (report §7). Press-in scale 0.92 / 100 ms is built into both styles
/// (INVARIANTS 5), so a call site never stacks `PressableScaleStyle` on top.
public nonisolated enum JIButtonMetrics {
    public static let height: CGFloat = JITileHeight.button.base
    public static let radius: CGFloat = 18
    /// The primary label colour on the accent (BUG-30).
    public static let primaryLabel = Color.black
}

public struct JIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.jiTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = JIButtonMetrics.height
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .jiFont(.body, weight: .semibold)
            .foregroundStyle(JIButtonMetrics.primaryLabel)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(theme.color(.info).opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: JIButtonMetrics.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: JIButtonMetrics.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? PressableScaleStyle.pressedScale : 1)
            .animation(JIMotion.press, value: configuration.isPressed)
    }
}

public struct JISecondaryButtonStyle: ButtonStyle {
    @Environment(\.jiTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = JIButtonMetrics.height
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: JIButtonMetrics.radius, style: .continuous)
        configuration.label
            .jiFont(.body, weight: .semibold)
            .foregroundStyle(theme.color(.text).opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(theme.color(.surface2), in: shape)
            .overlay(shape.strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? PressableScaleStyle.pressedScale : 1)
            .animation(JIMotion.press, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == JIPrimaryButtonStyle {
    /// The one primary action of a screen: accent fill, black label, 52 pt.
    static var jiPrimary: JIPrimaryButtonStyle { JIPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == JISecondaryButtonStyle {
    /// A secondary action: card fill + rim, 52 pt.
    static var jiSecondary: JISecondaryButtonStyle { JISecondaryButtonStyle() }
}
