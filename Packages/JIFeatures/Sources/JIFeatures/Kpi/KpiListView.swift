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
    /// B-57 W2 (B-73): the user's goals for the nutrition squares' captions.
    @Environment(\.nutritionGoals) private var nutritionGoals

    /// W-FIX2 BUG-21: a square opens its KPI detail (board 2/02). nil = display-only squares.
    private let onSelectKpi: ((String) -> Void)?

    public init(model: KpiListViewModel, onSelectKpi: ((String) -> Void)? = nil) {
        self.model = model
        self.onSelectKpi = onSelectKpi
    }

    public var body: some View {
        // W-GUI R4 (mockup 23): the catalogue of 104 pt squares with tick badges, grouped On Today /
        // Recovery / Nutrition under caps headers, on the page ground; Reset is the secondary.
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: rows
                }
                Text(kpiListCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
                // B-57 W1 board: no "Gate targets" section here — the gate rules are read-only in
                // Settings → Local data mirrors and edited per metric on KpiDetail.
                Button("Reset to defaults") { model.resetSelection(); announceTodayChange() }
                    .buttonStyle(.jiSecondary)
                    .padding(.top, JISpacing.s4)
                    .accessibilityLabel("Reset My KPIs to defaults")
                    .accessibilityIdentifier("kpi-reset-selection")
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle("My KPIs")
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    /// W-FIX3 C-a: "On Today" IS Today's squares (one selection) — tell a Today behind this sheet.
    private func announceTodayChange() { NotificationCenter.default.post(name: todayTilePrefsDidChange, object: nil) }

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
        VStack(alignment: .leading, spacing: 0) {
            Text(kpiListSubtitle)
                .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4)
            ForEach(KpiCatalogueGroup.allCases, id: \.self) { group in
                let items = kpiCatalogueItems(group: group, visible: model.visibleOrder, value: { model.value(for: $0) },
                                              today: String(Date().ISO8601Format().prefix(10)), goalCaption: { nutritionGoals.caption(for: $0, value: $1) })
                if !items.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        JISectionHeader(kpiListGroupHeader(group, count: items.count))
                    }
                    SquareGrid(items: items, family: squareTileFamily(catalog: true), onTap: onSelectKpi.map { open in { raw in kpiListDetailMetric(raw).map(open) } }, onBadge: { raw in
                        guard let id = KpiMetricId(rawValue: raw) else { return }   // Fibre/Sugar: display-only
                        if model.toggle(id, selected: group != .onToday) { announceTodayChange() }
                    })
                }
            }
        }
    }
}

/// W-FIX2 BUG-21: the metric a tapped My KPIs square opens — only registered KPIs have a detail
/// (Fibre / Sugar squares are display-only).
public nonisolated func kpiListDetailMetric(_ squareId: String) -> String? {
    KpiMetricId(rawValue: squareId)?.rawValue
}


// MARK: - W-GUI R4 (mockup 23) copy, pure

public nonisolated let kpiListSubtitle = "Every metric is a square. Ticked ones sit on Today."
public nonisolated let kpiListCaption = "Any square can go on a widget. Today holds \(KpiSelection.minSelected) to \(KpiSelection.maxSelected)."
/// "On Today · 6" for the first group; the others are their names.
public nonisolated func kpiListGroupHeader(_ group: KpiCatalogueGroup, count: Int) -> String {
    group == .onToday ? "\(group.rawValue) · \(count)" : group.rawValue
}
