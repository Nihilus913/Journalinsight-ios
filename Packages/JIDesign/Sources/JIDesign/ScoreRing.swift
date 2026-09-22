import SwiftUI

/// §4b small ring: one bounded value against a fixed scale or goal (Sleep score, Steps vs goal,
/// Calories vs goal, Body Battery). 44 pt, round caps, the §4 long fade, reveal on appear.
/// VoiceOver value "<n> of <max>". Never for baseline-relative metrics (HRV, RHR, ACWR).
public struct ScoreRing: View {
    public nonisolated static let defaultSize: CGFloat = 44
    let value: Double, max: Double, tint: Color
    @ScaledMetric private var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiRevealAnimations) private var revealAnimations
    @State private var shown: Double = 0

    /// Off for reduced motion and for snapshot renders (§8.5): the ring paints its FINAL value.
    private var animatesReveal: Bool { revealAnimations && !reduceMotion }

    public init(value: Double, max: Double, tint: Color, size: CGFloat = ScoreRing.defaultSize) {
        self.value = value; self.max = max; self.tint = tint
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var fraction: Double { ringFraction(value: value, max: max) }

    public var body: some View {
        let lineWidth = size * 0.14
        ZStack {
            Circle().stroke(theme.color(.nested), lineWidth: lineWidth)
            Circle().trim(from: 0, to: animatesReveal ? shown : fraction)
                .stroke(
                    AngularGradient(stops: ringFadeStops(tint), center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * fraction)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear { if animatesReveal { reveal() } }
        .onChange(of: value) { if animatesReveal { reveal() } }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(ringAccessibilityValue(value: value, max: max))
    }

    private func reveal() {
        withAnimation(JIMotion.standard) { shown = fraction }
    }
}
