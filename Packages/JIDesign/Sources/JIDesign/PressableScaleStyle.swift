import SwiftUI

/// Pressed scale factor: `PressableScaleStyle.pressedScale` while pressed, `1`
/// otherwise — Reduce Motion suppresses the scale unconditionally (opacity-only
/// fallback, rule 4 — no scale/translation while Reduce Motion is on).
public nonisolated func pressedScaleEffect(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
    isPressed && !reduceMotion ? PressableScaleStyle.pressedScale : 1
}

/// The one press style. 0.92 scale (≥ 8 % region change) within 100 ms — calibrated, not "subtle".
public struct PressableScaleStyle: ButtonStyle {
    public nonisolated static let pressedScale: CGFloat = 0.92
    public nonisolated static let pressedOpacity: Double = 0.85
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(pressedScaleEffect(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(configuration.isPressed ? JIMotion.press : JIMotion.overshoot, value: configuration.isPressed)
            .jiHaptic(.pressIn, trigger: configuration.isPressed) // DESIGN-5: routed through the JIHaptic ladder, fires once on press-in
    }
}
public extension ButtonStyle where Self == PressableScaleStyle { static var pressableScale: PressableScaleStyle { .init() } }
