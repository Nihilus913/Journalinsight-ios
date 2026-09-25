import AppIntents
import JICore
import JIDesign
import JISnapshot
import SwiftUI
import WidgetKit

/// W-B34 (B-36): configurable single-KPI widget. The user picks one `KpiMetricId` in the widget's
/// configuration (`SelectKpiIntent`, default readiness); the face reads that id from the
/// snapshot's `allKpis` via `HubSnapshot.kpi(_:)` — never a fixed top-N, never matched by label.
struct KpiWidget: Widget {
    let kind = "KpiWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectKpiIntent.self, provider: KpiTimelineProvider()) { entry in
            KpiWidgetView(snapshot: entry.snapshot, metric: entry.metric)
        }
        .configurationDisplayName("KPI")
        .description("One metric of your choice.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct KpiWidgetView: View {
    let snapshot: HubSnapshot?
    let metric: KpiMetricId
    @Environment(\.widgetFamily) private var family

    var body: some View {
        KpiWidgetFace(snapshot: snapshot, metric: metric, family: family)
            .containerBackground(widgetTheme.color(.bg), for: .widget)
    }
}

/// The face for one family, with the family passed in rather than read from the (read-only)
/// `widgetFamily` environment — so a host-side `ImageRenderer` harness can render every family.
struct KpiWidgetFace: View {
    let snapshot: HubSnapshot?
    let metric: KpiMetricId
    let family: WidgetFamily
    private let theme = widgetTheme

    private var def: KpiMetricDef { KpiMetrics.def(metric) }
    private var kpi: SnapshotKPI? { snapshot?.kpi(metric) }
    /// "—" when the snapshot lacks the KPI or its value (CLAUDE.md rule 5: never a bare "0").
    private var valueText: String { formatKpiValue(kpi?.value, decimals: def.decimals) }
    private var unitText: String? {
        guard kpi?.value != nil else { return nil }
        let unit = kpi?.unit ?? def.unit
        return unit.isEmpty ? nil : unit
    }

    var body: some View {
        content.jiTheme(.native)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            // B-73: "Protein 103 g to goal" for a macro KPI with a user goal; else the KPI text.
            Text(snapshot?.macros?.inlineText(for: metric) ?? inlineText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(def.label)
                    .jiFont(.caption, weight: .bold)
                    .lineLimit(1)
                valueRow(numeral: .numeralSmall)
                asOf
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            // B-73: "Left to your goals" once the user set a goal and Health food is readable.
            if let macros = snapshot?.macros { MacrosLeftFace(macros: macros) } else { kpiMedium }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(def.label)
                    .jiFont(.caption, weight: .bold)
                    .foregroundStyle(theme.color(.muted))
                    .lineLimit(2)
                Spacer(minLength: 0)
                valueRow(numeral: .numeralLarge)
                asOf
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var kpiMedium: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(def.label)
                    .jiFont(.subheadline, weight: .bold)
                    .foregroundStyle(theme.color(.muted))
                    .lineLimit(1)
                valueRow(numeral: .numeralHero)
                Spacer(minLength: 0)
                asOf
            }
            Spacer(minLength: 0)
        }
    }

    private func valueRow(numeral: JITypography.Token) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(valueText)
                .jiNumeral(numeral)
                .foregroundStyle(theme.color(.text))
                .lineLimit(1).minimumScaleFactor(0.5)
            if let unitText {
                Text(unitText)
                    .jiFont(.caption)
                    .foregroundStyle(theme.color(.muted))
            }
        }
    }

    @ViewBuilder private var asOf: some View {
        if let text = asOfText {
            Text(text)
                .jiFont(.micro)
                .foregroundStyle(theme.color(.muted))
                .lineLimit(1)
        } else if snapshot == nil {
            Text("No data yet")
                .jiFont(.micro)
                .foregroundStyle(theme.color(.muted))
        }
    }

    private var asOfText: String? {
        guard let lastSync = snapshot?.lastSync else { return nil }
        let stamp = Calendar.current.isDateInToday(lastSync)
            ? lastSync.formatted(date: .omitted, time: .shortened)
            : lastSync.formatted(.dateTime.day().month(.abbreviated))
        return "as of \(stamp)"
    }

    private var inlineText: String {
        [def.label, valueText, unitText].compactMap { $0 }.joined(separator: " ")
    }
}

// The entries carry the chosen KPI, so the static-timeline preview form covers both KPIs per family
// (the `using:` intent form only exists alongside a live `timelineProvider`).
#Preview("KPI — small", as: .systemSmall, widget: { KpiWidget() }, timeline: {
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .readiness)
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .weight)
    KpiEntry(date: .now, snapshot: nil, metric: .readiness)
})

#Preview("KPI — medium", as: .systemMedium, widget: { KpiWidget() }, timeline: {
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .weight)
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .readiness)
})

#Preview("KPI — medium macros", as: .systemMedium, widget: { KpiWidget() }, timeline: {
    // Preview data only: goals a user typed, never a shipped default.
    KpiEntry(date: .now, snapshot: .previewSeedWithMacros, metric: .protein)
})

#Preview("KPI — rectangular", as: .accessoryRectangular, widget: { KpiWidget() }, timeline: {
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .readiness)
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .weight)
})

#Preview("KPI — inline", as: .accessoryInline, widget: { KpiWidget() }, timeline: {
    KpiEntry(date: .now, snapshot: .previewSeedWithMacros, metric: .protein)
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .readiness)
    KpiEntry(date: .now, snapshot: .previewSeed, metric: .weight)
})

extension HubSnapshot {
    /// B-73 preview only: `previewSeed` plus macros left against goals a user typed.
    static var previewSeedWithMacros: HubSnapshot {
        var s = HubSnapshot.previewSeed
        s.macros = SnapshotMacros.make(goals: (1800, 155, 144, 49), eatenToday: (650, 52, 90, 20), healthReadable: true, asOf: .now)
        return s
    }
}
