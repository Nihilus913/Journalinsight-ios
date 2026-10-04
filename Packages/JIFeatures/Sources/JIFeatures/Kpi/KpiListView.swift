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
    /// W-FIX5 WD-2: the 7-day Load the Today square shows (nil = the square says why).
    @Environment(\.recoveryInsight) private var recoveryInsight

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
        .navigationTitle(kpiListTitle)
        .environment(\.jiHubOffline, !model.hubReachable)   // W-FIX11 H1-15: no green check while offline
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .task { await recoveryInsight?.refreshIfStale() }   // WD-2: the Load square's reading
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
            KpiCatalogueGrids(model: model, onSelectKpi: onSelectKpi)
        }
    }
}

/// W-TGT fixer 1f: the picker's square grids (On Today · Recovery · Nutrition) — the On Today
/// screen and Settings › Home & widgets draw the same ones. Captions read Targets ("goal" is
/// yours, "your normal" computed); food squares read Apple Health first (live, else cached).
struct KpiCatalogueGrids: View {
    @Bindable var model: KpiListViewModel
    let onSelectKpi: ((String) -> Void)?
    @Environment(\.nutritionGoals) private var nutritionGoals
    @Environment(\.targets) private var targets
    @Environment(\.targetsModel) private var targetsModel
    @Environment(\.recoveryInsight) private var recoveryInsight

    var body: some View {
        let doc = targetsModel?.document ?? targets
        ForEach(KpiCatalogueGroup.allCases, id: \.self) { group in
            let items = kpiCatalogueItems(group: group, visible: model.visibleOrder, value: { model.value(for: $0) },
                                          today: DayKey.today(now: Date()).iso,
                                          goalCaption: { kpiListGoalCaption($0, value: $1, targets: doc) ?? nutritionGoals.caption(for: $0, value: $1) },
                                          load: recoveryInsight?.loadReading, health: model.healthTotals,
                                          hub: model.nutrition)
            if !items.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    JISectionHeader(kpiListGroupHeader(group, count: items.count))
                }
                if group == .onToday, let note = kpiTodayFullNote(count: items.count) {
                    Text(note).jiFont(.footnote).foregroundStyle(JITheme.native.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kpi-list-today-full")
                }
                SquareGrid(items: items, family: squareTileFamily(catalog: true), onTap: onSelectKpi.map { open in { raw in kpiListDetailMetric(raw).map(open) } }, onBadge: { raw in
                    guard let id = KpiMetricId(rawValue: raw) else { return }   // Fibre/Sugar: display-only
                    if model.toggle(id, selected: group != .onToday) {
                        NotificationCenter.default.post(name: todayTilePrefsDidChange, object: nil)
                    }
                })
            }
        }
    }
}

/// W-FIX2 BUG-21: the metric a tapped My KPIs square opens — only registered KPIs have a detail
/// (Fibre / Sugar squares are display-only).
public nonisolated func kpiListDetailMetric(_ squareId: String) -> String? {
    KpiMetricId(rawValue: squareId)?.rawValue
}


/// W-TGT L3 (mock 05): the caption of a square whose goal lives in the targets document only
/// (steps, sleep, weight) — "goal 7,000" / "goal 7 h" / "goal 75.0", "no goal" without one; the
/// load square shows its band rule. nil = the nutrition captions decide (`NutritionGoalsSnapshot`).
public nonisolated func kpiListGoalCaption(_ id: KpiMetricId, value: Double?, targets: TargetsDocument?) -> String? {
    let doc = targets ?? .empty
    let metric: GoalMetric
    switch id {
    case .steps: metric = .steps
    // W-TGT fixer 2 R2: the Sleep square is the score (0–100) and its goal is hours — a caption
    // "goal 7.5 h" under "94" mixes the two, so the score square carries no goal line.
    case .sleep: return nil
    case .weight: metric = .weight
    case .acwr: return "band \(targetsNumber(doc.rule(.loadBandLow), 2))–\(targetsNumber(doc.rule(.loadBandHigh), 2))"
    // W-TGT fixer 1f (mock 05): the food squares say the goal too ("goal 1,617", "goal 155 g",
    // "no goal") — never a status word computed against another source's band.
    case .kcal, .protein, .carbs, .fat:
        guard let targets else { return nil }
        let m: GoalMetric = switch id { case .kcal: .kcal; case .protein: .protein; case .carbs: .carbs; default: .fat }
        return targets.goal(m).map { targetsGoalCaption(m, $0) } ?? "no goal"
    default: return nil
    }
    return doc.goal(metric).map { targetsGoalCaption(metric, $0) } ?? "no goal"
}

// MARK: - W-GUI R4 (mockup 23) copy, pure

/// The picker's title: it is Home & widgets › On Today (spec §4), no longer "My KPIs".
public nonisolated let kpiListTitle = "On Today"
public nonisolated let kpiListSubtitle = "Every metric is a square. Ticked ones sit on Today."
public nonisolated let kpiListCaption = "Any square can go on a widget. Today holds \(KpiSelection.minSelected) to \(KpiSelection.maxSelected)."
/// "On Today · 6" for the first group; the others are their names.
/// W-FIX11 H2-10: said under On Today once it holds the most squares (no "+" is offered then).
public nonisolated func kpiTodayFullNote(count: Int) -> String? {
    count >= KpiSelection.maxSelected ? "Today is full (\(count)). Untick one to add another." : nil
}

public nonisolated func kpiListGroupHeader(_ group: KpiCatalogueGroup, count: Int) -> String {
    group == .onToday ? "\(group.rawValue) · \(count)" : group.rawValue
}
