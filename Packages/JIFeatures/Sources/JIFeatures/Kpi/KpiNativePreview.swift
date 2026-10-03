// W-DEAD-2 D2-9: gallery/preview support — compiled into Debug only, never the installed app.
#if DEBUG
import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entries "KPIs" and "KPI detail". Both compose the shipping components
/// (`SquareGrid` via `kpiCatalogueItems`, `KpiDetailTrend`, `KpiAlertEditor`) over fixtures — the sweep never
/// builds a hub-backed view model, whose `.task` `ImageRenderer` would not run anyway.
private nonisolated enum L5KpiFixtures {
    /// 30 nights of HRV ending 2026-09-23, one night missing (left out of the chart, never a zero).
    static let history: [(date: String, value: Double?)] = (0..<30).map { i in
        let day = trainingStripISO(trainingStripCalendar.date(byAdding: .day, value: i - 29,
                                                              to: trainingStripDate("2026-09-23")!)!)
        return (date: day, value: i == 21 ? nil : [48, 50, 47, 53, 51, 49, 52][i % 7] + Double(i % 3))
    }
}

struct KpiListNativePreview: View {
    private let theme = JITheme.native
    /// B-57 W1: mirrors `KpiListView.rows` — the catalogue of squares over fixture values.
    private static let visible: [KpiMetricId] = [.hrv, .rhr, .sleep, .acwr]
    private static let values: [KpiMetricId: Double] = [.hrv: 52, .rhr: 54, .sleep: 81, .acwr: 1.08, .protein: 168, .weight: 104.2]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Every metric is a square. Ticked ones sit on Today; any of them can go on a widget.")
                .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
            ForEach(KpiCatalogueGroup.allCases, id: \.self) { group in
                let items = kpiCatalogueItems(group: group, visible: Self.visible, value: { Self.values[$0] })
                if !items.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.rawValue).jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if group == .onToday { Text("\(items.count)").jiFont(.subheadline).foregroundStyle(theme.color(.muted)) }
                    }
                    SquareGrid(items: items, family: squareTileFamily(catalog: true), onBadge: { _ in })
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}

struct KpiDetailNativePreview: View {
    /// W-GUI R2: one preview, three fixtures (HRV 07 / RHR 20 / Sleep 21).
    var metric: KpiMetricId = .hrv
    @State private var range: KpiDetailRange = .month
    @State private var threshold: Double = 45
    private let theme = JITheme.native
    private var unit: String { metric == .rhr ? "bpm" : (metric == .sleep ? "" : "ms") }
    private var value: Double { metric == .rhr ? 54 : (metric == .sleep ? 81 : 52) }
    private var label: String { metric == .rhr ? "Resting HR" : (metric == .sleep ? "Sleep" : "HRV") }
    private var history: [(date: String, value: Double?)] {
        L5KpiFixtures.history.map { ($0.date, $0.value.map { v in metric == .rhr ? v + 4 : (metric == .sleep ? v + 30 : v) }) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KpiDetailSourceLine(subtitle: kpiDetailSubtitle(metric), fetchedAt: nil, showsSynced: false)
            // The shipped value card over the fixture nights: number, status word, explanation.
            KpiDetailValueCard(valueText: value.formatted(.number.precision(.fractionLength(0))) + (unit.isEmpty ? "" : " \(unit)"), label: label,
                               status: kpiDetailStatus(history: history, value: value, unit: unit, decimals: 0),
                               asOf: nil, tint: metricTintRole(metric.rawValue), heroTint: metric == .sleep ? theme.color(.sleep) : nil)
            KpiDetailTrend(points: kpiDetailTrendPoints(history, range: range), label: label, unit: unit.isEmpty ? nil : unit, range: $range,
                           tint: metricTintRole(metric.rawValue))
            if let block = kpiDetailBlock(metric: metric, valueText: "\(Int(value)) \(unit)", sleepDuration: metric == .sleep ? "7 h 24" : nil) {
                JISectionHeader(block.title)
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { JIRowDivider().padding(.leading, 0) }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                                    Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                }
                                Spacer(minLength: 8)
                                Text(row.value).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(row.value.hasPrefix("—") ? .muted : .text))
                            }
                            .padding(.vertical, JISpacing.s3)
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                Text(block.caption).jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
            }
            KpiAlertEditor(sentence: kpiDetailPreviewThresholdSentence, value: $threshold, unit: "ms", decimals: 0,
                           saving: false, dirty: threshold != 45, error: nil, onSave: {})
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}


/// B-46 item 4 (fixer): the Gallery's KPI-detail mock renders the SAME copy as the shipped screen
/// — the sweep PNG showed the raw `hrv_weekly_avg >= …` key long after `KpiDetailView` was fixed.
/// Exposed as constants so a host test can assert them without rendering SwiftUI.
nonisolated let kpiDetailPreviewAlertHeader = "Alert"
nonisolated let kpiDetailPreviewThresholdSentence = kpiThresholdSentence(metricLabel: "HRV", operator: "<")
#endif
