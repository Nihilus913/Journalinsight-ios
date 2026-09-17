import SwiftUI
import JIDesign
import JISnapshot

/// DESIGN-6: mirrors `statChipAccessibilityLabel` (JIDesign/StatChip.swift) —
/// a missing value reads as "—", never a bare unit or a coerced 0.
public nonisolated func kpiValueText(_ kpi: SnapshotKPI) -> String {
    guard let value = kpi.value else { return "—" }
    let numeral = value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    guard let unit = kpi.unit, !unit.isEmpty else { return numeral }
    return "\(numeral) \(unit)"
}

public nonisolated func kpiAccessibilityLabel(_ kpi: SnapshotKPI) -> String {
    "\(kpi.label) \(kpiValueText(kpi))"
}

/// Third glance: the top "My KPIs" rows, scrollable if there are more than
/// fit the face. An empty/missing snapshot shows "No data yet" rather than
/// an empty list (rule 5).
public struct MyKpisGlance: View {
    let snapshot: HubSnapshot?
    public init(snapshot: HubSnapshot?) { self.snapshot = snapshot }

    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let kpis = snapshot?.kpis, !kpis.isEmpty {
                    ForEach(Array(kpis.enumerated()), id: \.offset) { _, kpi in
                        Surface(level: 2, padding: 10) {
                            HStack {
                                Text(kpi.label).font(.caption).foregroundStyle(JIColor.muted).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(kpiValueText(kpi)).font(.body.weight(.semibold)).foregroundStyle(JIColor.text)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(kpiAccessibilityLabel(kpi))
                    }
                } else {
                    SkeletonBlock(height: 32)
                    SkeletonBlock(height: 32)
                    Text("No data yet").font(.caption2).foregroundStyle(JIColor.muted)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
