import SwiftUI
import JICore
import JIDesign

/// KPI list screen (W3b-L2, P-kpi) — mirrors the oracle's `app/kpis.tsx` picker: every registered
/// `KpiMetricId` with its live value, matching gate target (if any), and a toggle + accessible
/// up/down reorder confined to the selected subset (`KpiSelection`, floor 3 / ceiling 8). Reachable
/// from `RootTabView`'s toolbar.
public struct KpiListView: View {
    @Bindable private var model: KpiListViewModel

    public init(model: KpiListViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: rows
                }
                KpiTargetsMirrorSection(targets: model.targets)
                Button("Reset to defaults") { model.resetSelection() }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Reset My KPIs to defaults")
                    .accessibilityIdentifier("kpi-reset-selection")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .navigationTitle("My KPIs")
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("My KPIs").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
            Text("Choose which numbers show on your KPI strip, and reorder them below.")
                .font(.subheadline).foregroundStyle(JIColor.muted)
        }
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.card, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 260) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("kpi-list-retry")
            }
        }
    }

    private var rows: some View {
        Surface(level: 2) {
            VStack(spacing: 4) {
                ForEach(model.prefs.order) { id in
                    row(for: id)
                    if id != model.prefs.order.last { Divider().overlay(JIColor.nested) }
                }
            }
        }
    }

    private func row(for id: KpiMetricId) -> some View {
        let def = KpiMetrics.def(id)
        let visible = model.visibleOrder
        let selected = !model.prefs.hidden.contains(id)
        let visibleIndex = visible.firstIndex(of: id)
        let valueText = formatKpiValue(model.value(for: id), decimals: def.decimals) + (def.unit.isEmpty ? "" : " \(def.unit)")
        let targetText = model.targetText(for: id)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(def.label).font(.subheadline.bold()).foregroundStyle(JIColor.text)
                Text(valueText).font(.caption).foregroundStyle(JIColor.muted)
                    .accessibilityLabel("\(def.label), \(valueText)")
                    .accessibilityIdentifier("kpi-row-value-\(id.rawValue)")
                if let targetText { Text("Target \(targetText)").font(.caption2).foregroundStyle(JIColor.mutedNested) }
            }
            Spacer()
            if selected, let visibleIndex {
                HStack(spacing: 6) {
                    Button { model.move(id, direction: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(visibleIndex <= 0)
                        .accessibilityLabel("Move \(def.label) up in My KPIs")
                        .accessibilityIdentifier("kpi-move-up-\(id.rawValue)")
                    Button { model.move(id, direction: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(visibleIndex >= visible.count - 1)
                        .accessibilityLabel("Move \(def.label) down in My KPIs")
                        .accessibilityIdentifier("kpi-move-down-\(id.rawValue)")
                }
                .buttonStyle(.pressableScale)
            }
            Toggle(isOn: Binding(get: { selected }, set: { model.toggle(id, selected: $0) })) { EmptyView() }
                .labelsHidden()
                .accessibilityLabel(selected ? "Remove \(def.label) from My KPIs" : "Add \(def.label) to My KPIs")
                .accessibilityIdentifier("kpi-toggle-\(id.rawValue)")
        }
        .opacity(selected ? 1 : 0.45)
        .padding(.vertical, 6)
    }
}
