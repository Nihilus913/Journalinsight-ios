import SwiftUI
import JICore
import JIDesign

/// Read-only mirror of every `plan.kpi_target` gate rule (W3b-L2). Editing one rule's threshold
/// happens inline on `KpiDetailView` for the metric it belongs to (PUT round trip) — this section
/// is a status view, not a second editor, mirroring the oracle's `KpiTargetsMirrorSection.tsx`
/// header comment.
public struct KpiTargetsMirrorSection: View {
    let targets: [KpiTarget]
    public init(targets: [KpiTarget]) { self.targets = targets }

    public var body: some View {
        Surface(level: 2) {
            VStack(alignment: .leading, spacing: 10) {
                Text("KPI TARGETS").font(.caption.bold()).foregroundStyle(JIColor.muted)
                if targets.isEmpty {
                    Text("Nothing mirrored yet — open KPIs once while online.")
                        .font(.footnote).foregroundStyle(JIColor.muted)
                } else {
                    VStack(spacing: 6) {
                        ForEach(targets) { target in
                            HStack {
                                Text(target.metric).font(.footnote.bold()).foregroundStyle(JIColor.text)
                                Spacer()
                                Text(rule(for: target)).font(.footnote).foregroundStyle(JIColor.muted)
                            }
                        }
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
