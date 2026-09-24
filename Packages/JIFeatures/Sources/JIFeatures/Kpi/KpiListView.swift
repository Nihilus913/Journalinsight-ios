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
                // B-57 W1 board: no "Gate targets" section here — the gate rules are read-only in
                // Settings → Local data mirrors and edited per metric on KpiDetail.
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Every metric is a square. Ticked ones sit on Today; any of them can go on a widget.")
                .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
            ForEach(KpiCatalogueGroup.allCases, id: \.self) { group in
                let items = kpiCatalogueItems(group: group, visible: model.visibleOrder, value: { model.value(for: $0) })
                if !items.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.rawValue).jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if group == .onToday { Text("\(items.count)").jiFont(.subheadline).foregroundStyle(theme.color(.muted)) }
                    }
                    SquareGrid(items: items, onBadge: { raw in
                        guard let id = KpiMetricId(rawValue: raw) else { return }   // Fibre/Sugar: display-only
                        _ = model.toggle(id, selected: group != .onToday)
                    })
                }
            }
        }
    }
}
