import SwiftUI

/// The one press style. 0.92 scale (≥ 8 % region change) within 100 ms — calibrated, not "subtle".
public struct PressableScaleStyle: ButtonStyle {
    public static let pressedScale: CGFloat = 0.92
    public static let pressedOpacity: Double = 0.85
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Self.pressedScale : 1)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(configuration.isPressed ? JIMotion.press : JIMotion.overshoot, value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { old, new in new && !old }
    }
}
public extension ButtonStyle where Self == PressableScaleStyle { static var pressableScale: PressableScaleStyle { .init() } }
