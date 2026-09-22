import SwiftUI

public nonisolated enum ReadinessBand: Sendable, Equatable { case danger, warn, go }
public nonisolated let readinessGoMin = 70.0
public nonisolated let readinessWarnMin = 40.0

public nonisolated func readinessBand(for value: Double) -> ReadinessBand {
    value >= readinessGoMin ? .go : value >= readinessWarnMin ? .warn : .danger
}
/// RN clock convention: 270° = 9 o'clock (0), 360° = 12 o'clock (50), 450° = 3 o'clock (100).
public nonisolated func gaugeAngle(for value: Double) -> Angle { .degrees(270 + (min(100, max(0, value)) / 100) * 180) }

/// §4 native fill: SwiftUI angles, 180° = 9 o'clock. Used for the gradient's end angle.
public nonisolated func gaugeFillEndAngle(for value: Double) -> Angle { .degrees(180 + 1.8 * min(100, max(0, value))) }

/// DESIGN-6: source-missing announces the shared "not from current source" copy — never a
/// bare dash. Pure + testable independent of SwiftUI's view lifecycle.
public nonisolated func readinessAccessibilityLabel(score: Double?, sourceMissing: Bool) -> String {
    if sourceMissing { return "Readiness \(sourceMissingCopy)" }
    return score.map { "Readiness \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "Readiness, no data yet"
}

private nonisolated struct ArcSegment: Shape {
    var from: Double, to: Double, lineWidth: CGFloat
    var lineCap: CGLineCap = .butt
    var animatableData: Double { get { to } set { to = newValue } }
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.maxY - lineWidth)
        let r = min(rect.width, rect.height * 2) / 2 - lineWidth
        var p = Path()
        // SwiftUI angles: 0 = 3 o'clock, clockwise. RN 270 (9 o'clock) = SwiftUI 180.
        p.addArc(center: c, radius: r, startAngle: gaugeAngle(for: from) - .degrees(90), endAngle: gaugeAngle(for: to) - .degrees(90), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
    }
}

public struct ReadinessArcGauge: View {
    let score: Double?, sourceMissing: Bool, size: CGFloat
    public init(score: Double?, sourceMissing: Bool = false, size: CGFloat = 180) { self.score = score; self.sourceMissing = sourceMissing; self.size = size }
    /// §4 native: stroke 16, scaled with the type size (§8.4).
    @ScaledMetric(relativeTo: .body) private var nativeTrack: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.jiRevealAnimations) private var revealAnimations
    /// Native reveal: animates 0 → score on first appearance (§4).
    @State private var displayed: Double = 0

    /// Off for reduced motion and for snapshot renders (§8.5): the arc paints its FINAL value.
    private var animatesReveal: Bool { revealAnimations && !reduceMotion }
    /// What the fill / head dot actually draw at: the animated state, or the final score.
    private var shownValue: Double { animatesReveal ? displayed : (score ?? 0) }

    public var body: some View {
        nativeBody
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readinessAccessibilityLabel(score: score, sourceMissing: sourceMissing))
    }

    // MARK: native (B-33 §4) — single track, long-fade fill, head dot, reveal

    private var nativeBody: some View {
        // §8.1: at AX sizes the numeral no longer fits inside the arc, so it reflows BELOW the
        // art instead of colliding with the stroke and the head dot. Below AX it stays inside.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    nativeArt
                    nativeNumerals
                }
            } else {
                ZStack(alignment: .bottom) {
                    nativeArt
                    nativeNumerals
                }
            }
        }
        .onAppear { if animatesReveal { reveal(to: score ?? 0) } }
        .onChange(of: score) { if animatesReveal { reveal(to: score ?? 0) } }
    }

    private var nativeArt: some View {
        ZStack(alignment: .bottom) {
            ArcSegment(from: 0, to: 100, lineWidth: nativeTrack, lineCap: .round).fill(theme.color(.nested))
            if let score, !sourceMissing {
                let tint = nativeBandColor(readinessBand(for: score))
                ArcSegment(from: 0, to: shownValue, lineWidth: nativeTrack, lineCap: .round)
                    .fill(AngularGradient(stops: ringFadeStops(tint), center: gradientCenter, startAngle: .degrees(180), endAngle: gaugeFillEndAngle(for: score)))
                headDot(at: shownValue, tint: tint)
            }
        }
        .frame(width: size, height: size / 2 + nativeTrack)
    }

    private var nativeNumerals: some View {
        numerals(color: score.map { nativeBandColor(readinessBand(for: $0)) } ?? theme.color(.muted), muted: theme.color(.muted))
    }

    /// The arc centre as a unit point of the gauge frame (`rect.maxY - lineWidth` in `ArcSegment`).
    private var gradientCenter: UnitPoint {
        let h = size / 2 + nativeTrack
        return UnitPoint(x: 0.5, y: (h - nativeTrack) / h)
    }

    private func reveal(to value: Double) {
        withAnimation(JIMotion.standard) { displayed = value }
    }

    private func nativeBandColor(_ b: ReadinessBand) -> Color {
        switch b { case .danger: theme.color(.danger); case .warn: theme.color(.reduced); case .go: theme.color(.go) }
    }

    private func headDot(at value: Double, tint: Color) -> some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height - nativeTrack)
            let r = min(g.size.width, g.size.height * 2) / 2 - nativeTrack
            let a = gaugeAngle(for: value) - .degrees(90)
            ZStack {
                Circle().fill(tint).frame(width: 18, height: 18).blur(radius: 4).opacity(0.35)
                Circle().fill(.white).frame(width: 10, height: 10)
            }
            .position(x: c.x + r * cos(a.radians), y: c.y + r * sin(a.radians))
        }
    }

    // MARK: shared numerals

    private func numerals(color: Color, muted: Color) -> some View {
        VStack(spacing: 2) {
            if sourceMissing {
                Text("—").jiNumeral(.numeralGauge).foregroundStyle(muted)
                Text(sourceMissingCopy).font(.caption).foregroundStyle(muted)
            } else if let score {
                Text(score, format: .number.precision(.fractionLength(0)))
                    .jiNumeral(.numeralGauge)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("readiness").font(.caption).foregroundStyle(muted)
            } else {
                Text("No data yet").font(.caption).foregroundStyle(muted)
            }
        }.padding(.bottom, 8)
    }
}
