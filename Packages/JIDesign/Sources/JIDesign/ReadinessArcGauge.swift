import SwiftUI

public nonisolated enum ReadinessBand: Sendable, Equatable { case danger, warn, go }
public nonisolated let readinessGoMin = 70.0
public nonisolated let readinessWarnMin = 40.0

public nonisolated func readinessBand(for value: Double) -> ReadinessBand {
    value >= readinessGoMin ? .go : value >= readinessWarnMin ? .warn : .danger
}
/// RN clock convention: 270° = 9 o'clock (0), 360° = 12 o'clock (50), 450° = 3 o'clock (100).
public nonisolated func gaugeAngle(for value: Double) -> Angle { .degrees(270 + (min(100, max(0, value)) / 100) * 180) }

private func bandColor(_ b: ReadinessBand) -> Color { switch b { case .danger: JIColor.danger; case .warn: JIColor.reduced; case .go: JIColor.go } }

/// DESIGN-6: source-missing announces the shared "not from current source" copy — never a
/// bare dash. Pure + testable independent of SwiftUI's view lifecycle.
public nonisolated func readinessAccessibilityLabel(score: Double?, sourceMissing: Bool) -> String {
    if sourceMissing { return "Readiness \(sourceMissingCopy)" }
    return score.map { "Readiness \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "Readiness, no data yet"
}

private nonisolated struct ArcSegment: Shape {
    var from: Double, to: Double, lineWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.maxY - lineWidth)
        let r = min(rect.width, rect.height * 2) / 2 - lineWidth
        var p = Path()
        // SwiftUI angles: 0 = 3 o'clock, clockwise. RN 270 (9 o'clock) = SwiftUI 180.
        p.addArc(center: c, radius: r, startAngle: gaugeAngle(for: from) - .degrees(90), endAngle: gaugeAngle(for: to) - .degrees(90), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}

public struct ReadinessArcGauge: View {
    let score: Double?, sourceMissing: Bool, size: CGFloat
    public init(score: Double?, sourceMissing: Bool = false, size: CGFloat = 180) { self.score = score; self.sourceMissing = sourceMissing; self.size = size }
    private let track: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack(alignment: .bottom) {
            ArcSegment(from: 0, to: 40, lineWidth: track).fill(bandColor(.danger).opacity(0.35))
            ArcSegment(from: 40, to: 70, lineWidth: track).fill(bandColor(.warn).opacity(0.35))
            ArcSegment(from: 70, to: 100, lineWidth: track).fill(bandColor(.go).opacity(0.35))
            if let score, !sourceMissing {
                needle(at: score)
            }
            VStack(spacing: 2) {
                if sourceMissing {
                    Text("—").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(JIColor.muted)
                    Text(sourceMissingCopy).font(.caption).foregroundStyle(JIColor.muted)
                } else if let score {
                    Text(score, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(bandColor(readinessBand(for: score)))
                        .contentTransition(.numericText())
                    Text("readiness").font(.caption).foregroundStyle(JIColor.muted)
                } else {
                    Text("No data yet").font(.caption).foregroundStyle(JIColor.muted)
                }
            }.padding(.bottom, 8)
        }
        .frame(width: size, height: size / 2 + track)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readinessAccessibilityLabel(score: score, sourceMissing: sourceMissing))
    }

    private func needle(at value: Double) -> some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height - track)
            let r = min(g.size.width, g.size.height * 2) / 2 - track
            let a = gaugeAngle(for: value) - .degrees(90)
            Circle().fill(JIColor.text)
                .overlay(Circle().stroke(bandColor(readinessBand(for: value)), lineWidth: 3))
                .frame(width: 16, height: 16)
                .position(x: c.x + r * cos(a.radians), y: c.y + r * sin(a.radians))
                .animation(reduceMotion ? nil : JIMotion.reveal, value: value)
        }
    }
}
