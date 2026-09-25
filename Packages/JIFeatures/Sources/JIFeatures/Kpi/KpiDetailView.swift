import SwiftUI
import Charts
import JICore
import JIDesign

/// KPI detail screen (W3b-L2, P-kpi) — reachable from a Today tile tap or a `ji://kpi-detail`
/// deep link (`RootTabView`). Live headline + Swift Charts history (`KpiMetrics.history`) plus,
/// when this metric has a matching gate rule, an inline threshold editor that round-trips through
/// `KpiTargetsProviding.updateKpiTarget` (PUT).
public struct KpiDetailView: View {
    @Bindable private var model: KpiDetailViewModel
    /// The alert stepper's working value (the rule's threshold until the reader steps it).
    @State private var threshold: Double = 0
    /// B-57 W1 board: 7 D / 30 D / 90 D above the trend.
    @State private var range: KpiDetailRange = .month
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: KpiDetailViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KpiDetailSourceLine(subtitle: kpiSourceSubtitle(model.metric), fetchedAt: model.fetchedAt,
                                    showsSynced: isNutritionKpi(model.metric))
                headline
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        .navigationTitle(model.def.label)
        .refreshable { await model.refresh() }
        .task {
            if !model.hasLiveResult { await model.load() }
            syncThreshold()
        }
        .onChange(of: model.target?.threshold) { _, _ in syncThreshold() }
        .animation(JIMotion.standard, value: model.phase)
    }

    private func syncThreshold() {
        if let t = model.target?.threshold { threshold = t }
    }

    /// §5: the screen's name is the navigation title. B-57 W1 board: the value card carries its
    /// status word and explanation; the nutrition variant has its own hero inside the panel.
    @ViewBuilder
    private var headline: some View {
        if !isNutritionKpi(model.metric) {
            let unit = model.def.unit
            KpiDetailValueCard(
                valueText: formatKpiValue(model.value, decimals: model.def.decimals) + (unit.isEmpty ? "" : " \(unit)"),
                label: model.def.label,
                status: kpiDetailStatus(history: model.history, value: model.value, unit: unit, decimals: model.def.decimals),
                asOf: model.asOfLabel
            )
        }
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 160) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("kpi-detail-retry")
            }
        }
    }

    @ViewBuilder
    private var loaded: some View {
        if isNutritionKpi(model.metric) { KpiNutritionPanel(rows: model.nutrition, goals: model.goals?.nutrition, macro: model.metric) }
        chartSection
        if model.target != nil { editor }
    }

    @ViewBuilder
    private var chartSection: some View {
        KpiDetailTrend(points: kpiDetailTrendPoints(model.history, range: range), label: model.def.label,
                       unit: model.def.unit.isEmpty ? nil : model.def.unit, range: $range)
    }

    @ViewBuilder
    private var editor: some View {
        // B-46 device feedback 4: never the raw `plan.kpi_target` key — the rule in the metric's
        // own words. B-57 W1 board: a − / + stepper and a full-width "Save alert".
        if let target = model.target {
            KpiAlertEditor(
                sentence: kpiThresholdSentence(metricLabel: model.def.label, operator: target.operator),
                value: $threshold, unit: model.def.unit, decimals: model.def.decimals,
                saving: model.saving, dirty: threshold != target.threshold, error: model.saveError,
                onSave: { Task { await model.saveThreshold(threshold) } }
            )
        }
    }
}
