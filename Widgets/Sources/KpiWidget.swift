import JICore
import JIDesign
import JISnapshot
import SwiftUI
import WidgetKit

/// Home-screen "My KPIs" widget: top rows from the snapshot's `kpis` array.
struct KpiWidget: Widget {
    let kind = "KpiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            KpiWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("My KPIs")
        .description("Your top tracked metrics.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

private struct KpiWidgetView: View {
    let snapshot: HubSnapshot?

    var body: some View {
        if let snapshot, !snapshot.kpis.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("My KPIs")
                    .font(.caption.bold())
                    .foregroundStyle(JIColor.muted)
                ForEach(snapshot.kpis.prefix(3), id: \.label) { kpi in
                    HStack {
                        Text(kpi.label)
                            .font(.caption)
                            .foregroundStyle(JIColor.text)
                        Spacer()
                        Text(formatted(kpi))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(JIColor.text)
                    }
                }
            }
            .containerBackground(JIColor.bg, for: .widget)
        } else {
            // Honest empty state — never a bare "0" row (CLAUDE.md rule 5).
            VStack(alignment: .leading, spacing: 4) {
                Text("My KPIs")
                    .font(.caption.bold())
                    .foregroundStyle(JIColor.muted)
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(JIColor.muted)
            }
            .containerBackground(JIColor.bg, for: .widget)
        }
    }

    private func formatted(_ kpi: SnapshotKPI) -> String {
        guard let value = kpi.value else { return "--" }
        let numberText = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
        guard let unit = kpi.unit, !unit.isEmpty else { return numberText }
        return "\(numberText) \(unit)"
    }
}

#Preview("KPIs — medium", as: .systemMedium, widget: { KpiWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
    SnapshotEntry(date: .now, snapshot: nil)
})
