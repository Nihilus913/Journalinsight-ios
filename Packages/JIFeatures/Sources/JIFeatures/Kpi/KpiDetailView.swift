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
    @State private var thresholdText: String = ""
    /// §2b.3 Health range picker above the trend.
    @State private var range: TrendRange = .month
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: KpiDetailViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                StalenessBanner(fetchedAt: nil, hubReachable: model.hubReachable)
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
            syncThresholdText()
        }
        .onChange(of: model.target?.threshold) { _, _ in syncThresholdText() }
        .animation(JIMotion.standard, value: model.phase)
    }

    private func syncThresholdText() {
        thresholdText = model.target.map { formatKpiValue($0.threshold, decimals: 2) } ?? ""
    }

    /// §5: the screen's name is the navigation title; the card keeps only the live number.
    private var headline: some View {
        let unit = model.def.unit
        let text = formatKpiValue(model.value, decimals: model.def.decimals) + (unit.isEmpty ? "" : " \(unit)")
        return Surface {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .jiNumeral(.numeralLarge).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(model.def.label)
                    .accessibilityValue(text)
                    .accessibilityIdentifier("kpi-detail-value")
                // B-46 item 3: a fallback reading is labelled with the day it came from, so an
                // older number is never presented as today's.
                if let asOf = model.asOfLabel {
                    Text(asOf).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("kpi-detail-as-of")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        chartSection
        if model.target != nil { editor }
    }

    /// The history as `TrendPoint`s, newest `range.days` days. A day with no reading is omitted,
    /// never plotted as a zero (rule 5).
    private var trendPoints: [TrendPoint] {
        model.history
            .compactMap { point -> TrendPoint? in
                guard let value = point.value, let date = trainingStripDate(point.date) else { return nil }
                return TrendPoint(date: date, value: value)
            }
            .sorted { $0.date < $1.date }
            .suffix(range.days)
    }

    @ViewBuilder
    private var chartSection: some View {
        JISectionHeader("Trend")
        Surface {
            // §2b.3: the Health chart — D/W/M/6M/Y picker, trailing axis, dashed average,
            // "Show All Data ›". Empty renders its own "No data yet" (rule 5).
            TrendChart(points: trendPoints, tint: theme.color(.info),
                       unit: model.def.unit.isEmpty ? nil : model.def.unit, range: $range, showAll: nil)
                .accessibilityLabel("\(model.def.label) trend")
                .accessibilityIdentifier("kpi-detail-chart")
        }
    }

    @ViewBuilder
    private var editor: some View {
        // B-46 device feedback 4: the section used to be headed "Target threshold" over the raw
        // `plan.kpi_target` row ("sleep_score_7d < … [55.00] Save"), which reads as "type your
        // sleep score in here". The header is now what the rule DOES, and the line above the
        // field is a sentence in the metric's own words — never the snake_case column key.
        JISectionHeader("Alert")
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                if let target = model.target {
                    Text(kpiThresholdSentence(metricLabel: model.def.label, operator: target.operator))
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("kpi-detail-threshold-label")
                }
                HStack(spacing: 10) {
                    TextField(model.def.unit.isEmpty ? "Threshold" : "Threshold (\(model.def.unit))", text: $thresholdText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Threshold")
                        .accessibilityIdentifier("kpi-detail-threshold-field")
                    Button("Save") {
                        guard let value = Double(thresholdText) else { return }
                        Task { await model.saveThreshold(value) }
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.color(.info))
                    .disabled(model.saving || Double(thresholdText) == nil)
                    .accessibilityLabel("Save target threshold")
                    .accessibilityIdentifier("kpi-detail-threshold-save")
                }
                if let saveError = model.saveError {
                    Text(saveError).jiFont(.footnote).foregroundStyle(theme.color(.reduced))
                }
            }
        }
    }
}
