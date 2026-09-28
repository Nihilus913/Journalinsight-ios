import SwiftUI
import JICore

// W-TGT L3 (mock 05, spec §4) — Home & widgets › On Today: the square picker (the screen that was
// Settings › My KPIs) is layout, so it lives with the rest of the Home layout (B-41: home = card
// order). Its captions read Targets ("goal" = yours, "your normal" = computed); a square opens its
// detail, where the Targets card edits the goal.
public struct OnTodaySection: SettingsSection {
    public nonisolated static let sectionId = "tgt.onToday"
    public let id = Self.sectionId
    public let title = "On Today"
    public let systemImage = "square.grid.3x2"
    public let sortKey = SettingsSortKey.preferences + 11
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { OnTodaySectionRows() }
}

/// "6 of 12" — the squares on Today out of every registered KPI (mock 05 header).
public nonisolated func onTodayTrailing(chosen: Int, total: Int = KpiMetricId.allCases.count) -> String {
    chosen == 0 ? settingsKpisTrailing(0) : "\(chosen) of \(total)"
}

private struct OnTodaySectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Section {
            if let kpis = model.kpiListModel {
                NavigationLink {
                    // W-FIX3 fixer C-e: a square opens its KPI detail (as the shell's My KPIs sheet).
                    KpiListView(model: kpis, onSelectKpi: model.kpiSelectAction)
                        .navigationDestination(item: Binding(get: { model.kpiDetailMetric },
                                                             set: { model.kpiDetailMetric = $0 })) { metric in
                            if let detail = model.kpiDetailModel, detail.metric == metric {
                                KpiDetailView(model: detail)
                            } else {
                                ContentUnavailableView("KPI unavailable", systemImage: "chart.line.uptrend.xyaxis")
                            }
                        }
                } label: {
                    SettingsLinkLabel(title: "On Today", subtitle: "The squares on Today, \(KpiSelection.minSelected) to \(KpiSelection.maxSelected), and their order",
                                      trailing: onTodayTrailing(chosen: model.kpiSelectedCount))
                }
                .accessibilityLabel("On Today")
                .accessibilityIdentifier("settings.row.onToday")
            } else {
                SettingsLinkLabel(title: "On Today",
                                  subtitle: settingsHubOnlySubtitle(action: "choose KPIs", hubConfigured: model.connection.host != nil,
                                                                    dataSource: ProviderSwitch.shared.kind))
                    .accessibilityIdentifier("settings.row.onToday.unavailable")
            }
        }
    }
}
