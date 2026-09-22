import SwiftUI
import JICore
import JIDesign

/// Read-only mirror of every `plan.kpi_target` gate rule (W3b-L2). Editing one rule's threshold
/// happens inline on `KpiDetailView` for the metric it belongs to (PUT round trip) — this section
/// is a status view, not a second editor, mirroring the oracle's `KpiTargetsMirrorSection.tsx`
/// header comment.
public struct KpiTargetsMirrorSection: View {
    let targets: [KpiTarget]
    @Environment(\.jiTheme) private var theme
    public init(targets: [KpiTarget]) { self.targets = targets }

    public var body: some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if targets.isEmpty {
                    Text("Nothing mirrored yet — open KPIs once while online.")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // §2b.2: one 44-pt inset-grouped row per mirrored gate rule.
                    ForEach(Array(targets.enumerated()), id: \.element.id) { idx, target in
                        JIRow(title: target.metric, systemImage: "target", tint: theme.color(.info)) {
                            Text(rule(for: target))
                        }
                        .accessibilityLabel("\(target.metric) target")
                        .accessibilityValue(rule(for: target))
                        .accessibilityIdentifier("kpi-target-\(target.metric)")
                        if idx != targets.count - 1 { Divider().overlay(theme.color(.hairlineNested)).padding(.leading, 40) }
                    }
                }
            }
        }
    }

    private func rule(for target: KpiTarget) -> String {
        if target.operator == "between", let hi = target.thresholdHi {
            return "\(formatted(target.threshold))–\(formatted(hi))"
        }
        return "\(target.operator) \(formatted(target.threshold))"
    }

    private func formatted(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }
}
