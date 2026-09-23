import SwiftUI
import JICore
import JIDesign

// MARK: - Pure helpers (host-tested)

/// W-B57b (B-61): where the signal's value sits on its own scale, 0…1, clamped. `nil` when the
/// value is missing — rule 5: the arc then shows only its muted track, never a zero fill.
public nonisolated func gateSignalFraction(_ s: GateSignal) -> Double? {
    guard let v = s.value else { return nil }
    return scaleFraction(v, s)
}

/// Where the threshold tick sits on the same scale, 0…1.
public nonisolated func gateSignalThresholdFraction(_ s: GateSignal) -> Double {
    scaleFraction(s.threshold, s)
}

private nonisolated func scaleFraction(_ v: Double, _ s: GateSignal) -> Double {
    let span = s.scaleMax - s.scaleMin
    guard span > 0 else { return 0 }
    return min(1, max(0, (v - s.scaleMin) / span))
}

/// The hub's status is the tint — the app never re-derives pass/amber/red.
public nonisolated func gateSignalColorRole(_ status: GateSignalStatus) -> JIColorRole {
    switch status {
    case .pass: .go
    case .amber: .reduced
    case .red: .danger
    case .missing: .nested
    }
}

/// "—" for a missing value (rule 5); sleep time keeps one decimal (6.0 h is the threshold).
public nonisolated func gateSignalValueText(_ s: GateSignal) -> String {
    guard let v = s.value else { return "—" }
    return v.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : 0)))
}

public nonisolated func gateSignalAccessibilityLabel(_ s: GateSignal) -> String {
    let thr = s.threshold.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : 0)))
    guard s.value != nil else { return "\(s.label), not synced yet, threshold \(thr)" }
    let value = [gateSignalValueText(s), s.unit.isEmpty ? nil : s.unit].compactMap { $0 }.joined(separator: " ")
    return "\(s.label) \(value), \(s.status.rawValue), threshold \(thr)"
}

// MARK: - View

/// W-B57b (B-61) Decide's "why": one small half-arc per `morning_go.evaluate` input (sleep, HRV,
/// RHR, sleep time) — the value on its scale, the threshold marked, tinted by the hub's status.
/// Tapping any arc opens the gate rationale (same destination as the Day hero).
public struct GateSignalArcsRow: View {
    let signals: [GateSignal]
    @Environment(\.gateRationaleModel) private var rationaleModel
    @Environment(\.gateRespondModel) private var respondModel
    @State private var showRationale = false

    public init(signals: [GateSignal]) { self.signals = signals }

    public var body: some View {
        let row = Columns(minimum: 58, spacing: 8) {
            ForEach(signals) { s in
                Button { if rationaleModel != nil { showRationale = true } } label: {
                    GateSignalArc(signal: s)
                }
                .buttonStyle(.pressableScale)
                .accessibilityLabel(gateSignalAccessibilityLabel(s))
                .accessibilityHint(rationaleModel == nil ? "" : "Opens the readiness rationale")
                .accessibilityIdentifier("today.decide.signal.\(s.key)")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.decide.signals")
        if let rationaleModel {
            row.navigationDestination(isPresented: $showRationale) {
                gateRationaleScreen(model: rationaleModel, respondModel: respondModel)
            }
        } else {
            row
        }
    }
}

/// One half-arc: `Circle().trim` like `ReadinessArcGauge`'s geometry (9 o'clock → 3 o'clock).
struct GateSignalArc: View {
    let signal: GateSignal
    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var stroke: CGFloat = 6
    @Environment(\.jiTheme) private var theme

    var body: some View {
        let tint = theme.color(gateSignalColorRole(signal.status))
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                arc(to: 1).stroke(theme.color(.nested), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                if let f = gateSignalFraction(signal), f > 0 {
                    arc(to: f).stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
                thresholdTick
                Text(gateSignalValueText(signal))
                    .jiFont(.footnote, weight: .semibold)
                    .foregroundStyle(signal.value == nil ? theme.color(.muted) : theme.color(.text))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: width, height: width / 2 + stroke / 2)
            Text(signal.label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// The upper half of a circle of diameter `width`, drawn from 9 o'clock clockwise to `f`.
    private func arc(to f: Double) -> some Shape {
        Circle()
            .trim(from: 0.5, to: 0.5 + 0.5 * f)
            .size(width: width - stroke, height: width - stroke)
            .offset(x: stroke / 2, y: stroke / 2)
    }

    /// A short radial mark across the track at the threshold.
    private var thresholdTick: some View {
        GeometryReader { g in
            let r = (width - stroke) / 2
            let c = CGPoint(x: g.size.width / 2, y: stroke / 2 + r)
            let a = Double.pi * (1 + gateSignalThresholdFraction(signal))   // 180° … 360°
            let inner = r - stroke * 0.9, outer = r + stroke * 0.9
            Path { p in
                p.move(to: CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a)))
                p.addLine(to: CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a)))
            }
            .stroke(theme.color(.text), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
