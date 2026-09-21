import SwiftUI
import JICore
import JIDesign

/// KPI list screen (W3b-L2, P-kpi) — mirrors the oracle's `app/kpis.tsx` picker: every registered
/// `KpiMetricId` with its live value, matching gate target (if any), and a toggle + accessible
/// up/down reorder confined to the selected subset (`KpiSelection`, floor 3 / ceiling 8). Reachable
/// from `RootTabView`'s toolbar.
public struct KpiListView: View {
    @Bindable private var model: KpiListViewModel
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: KpiListViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: rows
                }
                JISectionHeader("Gate targets")
                KpiTargetsMirrorSection(targets: model.targets)
                Button("Reset to defaults") { model.resetSelection() }
                    .buttonStyle(.bordered)
                    .tint(theme.color(.info))
                    .accessibilityLabel("Reset My KPIs to defaults")
                    .accessibilityIdentifier("kpi-reset-selection")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        .navigationTitle("My KPIs")
        #if os(iOS)
        // §5: the header's second line becomes the navigation subtitle.
        .navigationSubtitle("Choose which numbers show on your KPI strip")
        #endif
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 260) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("kpi-list-retry")
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            JISectionHeader("My KPIs")
            Surface(padding: 16) {
                VStack(spacing: 0) {
                    ForEach(model.prefs.order) { id in
                        row(for: id)
                        if id != model.prefs.order.last { Divider().overlay(theme.color(.hairlineNested)) }
                    }
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

        return KpiSelectionRow(
            label: def.label, valueText: valueText, targetText: model.targetText(for: id),
            selected: selected,
            canMoveUp: selected && (visibleIndex ?? 0) > 0,
            canMoveDown: selected && visibleIndex != nil && visibleIndex! < visible.count - 1,
            showsReorder: selected && visibleIndex != nil,
            identifierSuffix: id.rawValue,
            onMoveUp: { model.move(id, direction: -1) },
            onMoveDown: { model.move(id, direction: 1) },
            onToggle: { model.toggle(id, selected: $0) }
        )
    }
}
