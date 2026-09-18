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

    public init(model: KpiDetailViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: nil, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.def.label).font(.largeTitle.bold()).foregroundStyle(JIColor.text)
            let unit = model.def.unit
            Text(formatKpiValue(model.value, decimals: model.def.decimals) + (unit.isEmpty ? "" : " \(unit)"))
                .font(.title2.bold()).foregroundStyle(JIColor.text)
                .accessibilityLabel(model.def.label)
                .accessibilityValue(formatKpiValue(model.value, decimals: model.def.decimals) + (unit.isEmpty ? "" : " \(unit)"))
                .accessibilityIdentifier("kpi-detail-value")
        }
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.card, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 160) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
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

    @ViewBuilder
    private var chartSection: some View {
        let points = model.history
        if points.compactMap(\.value).isEmpty {
            Surface { Text("No data yet").foregroundStyle(JIColor.muted) }
        } else {
            Surface(level: 2) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trend").font(.caption).foregroundStyle(JIColor.muted)
                    Chart {
                        ForEach(points, id: \.date) { point in
                            if let value = point.value {
                                LineMark(x: .value("Date", point.date), y: .value(model.def.label, value))
                                    .foregroundStyle(JIColor.mutedNested)
                                    .symbol(.circle)
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 160)
                    .accessibilityLabel("\(model.def.label) trend")
                    .accessibilityIdentifier("kpi-detail-chart")
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        Surface(level: 2) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Target threshold").font(.caption).foregroundStyle(JIColor.muted)
                if let target = model.target {
                    Text("\(target.metric) \(target.operator) …").font(.footnote).foregroundStyle(JIColor.mutedNested)
                }
                HStack(spacing: 10) {
                    TextField("Threshold", text: $thresholdText)
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
                    .buttonStyle(.pressableScale)
                    .disabled(model.saving || Double(thresholdText) == nil)
                    .accessibilityLabel("Save target threshold")
                    .accessibilityIdentifier("kpi-detail-threshold-save")
                }
                if let saveError = model.saveError {
                    Text(saveError).font(.footnote).foregroundStyle(JIColor.reduced)
                }
            }
        }
    }
}
