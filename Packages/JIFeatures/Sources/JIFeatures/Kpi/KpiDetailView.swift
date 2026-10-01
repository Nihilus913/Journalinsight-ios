import SwiftUI
import Charts
import JICore
import JICompute
import JIDesign

/// KPI detail screen (W3b-L2, P-kpi) — reachable from a Today tile tap or a `ji://kpi-detail`
/// deep link (`RootTabView`). Live headline + Swift Charts history (`KpiMetrics.history`) plus the
/// W-TGT Targets card (Goal · Rule · Your normal, Edit → the Settings › Targets editor sheet),
/// which replaced the inline threshold editor (spec §4).
public struct KpiDetailView: View {
    /// BUG-09 (W-FIX2): the screen OWNS its model. The shell's `navigationDestination` closure
    /// re-runs on every shell re-render (a deep link focuses the tab, then clears the pending
    /// link) and builds a brand-new model each time; a plain stored model was swapped for that
    /// fresh, never-loaded one — the skeleton plus "— No data" stuck on screen, and the phase
    /// animation re-laid the scroll view mid-push into the safe-area inset loop (the hang).
    /// `@State` keeps the first model for the screen's lifetime; later ones are discarded.
    @State private var model: KpiDetailViewModel
    /// B-57 W1 board: 7 D / 30 D / 90 D above the trend.
    @State private var range: KpiDetailRange = .month
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native
    /// W-FIX4 PF-04 (B-57 W3): the shell's one sync instant for the source line's pill.
    @Environment(\.jiSyncedAt) private var syncedAt

    public init(model: KpiDetailViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        #if DEBUG
        let _ = { model.debugRenderCount += 1 }()
        #endif
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                // PF-04: the pill is the one rule (newer of hub sync / HealthKit upload), never the fetch time.
                KpiDetailSourceLine(subtitle: kpiDetailSubtitle(model.metric),
                                    fetchedAt: oneSyncPillDate(injected: syncedAt, lastUpload: healthKitLastUploadDate()),
                                    showsSynced: isNutritionKpi(model.metric))
                headline
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .loaded: loaded
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()   // W-GUI R2 (report §7 rule 2)
        .jiTheme(.native)
        .navigationTitle(model.def.label)
        .refreshable { await model.refresh() }
        .task {
            if !model.hasLiveResult { await model.load() }
        }
        // BUG-09: no implicit animation on `phase`. Animating the skeleton → content swap resized
        // the scroll view's content while the push was still in flight (a deep link pushes and
        // loads at once), and UIKit re-entered its safe-area inset update every frame — the main
        // thread spun at 100 % CPU with the screen frozen mid-push.
    }

    /// §5: the screen's name is the navigation title. B-57 W1 board: the value card carries its
    /// status word and explanation; the nutrition variant has its own hero inside the panel.
    @ViewBuilder
    private var headline: some View {
        if !isNutritionKpi(model.metric) {
            let unit = model.def.unit
            KpiDetailValueCard(
                valueText: kpiDetailNumber(model.value, decimals: model.def.decimals) + (unit.isEmpty ? "" : " \(unit)"),
                label: model.def.label,
                status: kpiDetailStatus(history: model.history, value: model.value, unit: unit, decimals: model.def.decimals,
                                        hubCalibrating: model.calibrationCaption != nil,
                                        valueDate: model.showsLoadMinutes ? nil : model.latest?.date,
                                        today: RecoveryInsightService.localDayKey(Date())),
                asOf: model.asOfLabel,
                tint: metricTintRole(model.metric.rawValue),
                heroTint: model.metric == .sleep ? theme.color(.sleep) : nil
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
        if isNutritionKpi(model.metric) { KpiNutritionPanel(rows: model.nutrition,
                                                               macro: Binding(get: { model.metric }, set: { model.selectMetric($0) })) }
        // BUG-40: on nutrition the panel's 7-day NormalBar replaces the line trend.
        if kpiDetailShowsLineTrend(model.metric) {
            normalSection
            chartSection
            // B-57 W4 (board 2/03): daytime HRV row + the medication check, HRV only.
            if model.metric == .hrv { DaytimeHrvSection(model: model) }
            // W-GUI R2 (mockups 07 / 20): the table under the chart and the per-metric block.
            tableCard
            if let block = kpiDetailBlock(metric: model.metric, valueText: kpiDetailValueText, sleepDuration: kpiDetailSleepDuration,
                                          deepRem: kpiDetailDeepRem, sdnn: kpiDetailSdnn) {
                blockSection(block)
            }
        } else if model.metric == .sleep, let block = kpiDetailBlock(metric: .sleep, valueText: kpiDetailValueText, sleepDuration: kpiDetailSleepDuration,
                                                                        deepRem: kpiDetailDeepRem) {
            blockSection(block)
        }
        // W-TGT: Goal · Rule · Your normal, one Edit (the same sheet as Settings › Targets).
        KpiDetailTargetsCard(metric: model.metric, normal: kpiNormal.normal, sevenDay: kpiNormal.sevenDay,
                             decimals: model.def.decimals, unit: model.def.unit)
        if isNutritionKpi(model.metric) {
            // W-TGT: "Edit macro goals" is the Targets card's Edit now — no second path.
            KpiNutritionLinks(metricLabel: model.def.label, goalsSetupModel: nil)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        KpiDetailTrend(points: kpiDetailTrendPoints(model.history, range: range), label: model.def.label,
                       unit: model.def.unit.isEmpty ? nil : model.def.unit, range: $range,
                       tint: metricTintRole(model.metric.rawValue),
                       legend: kpiDetailLegendText(kpiNormal.normal, decimals: model.def.decimals),
                       normal: kpiNormal.normal)
    }

    /// W-B57-W3 fixer: one normal for the NormalBar, the chart legend and the table row.
    /// W-FIX10 R-04: no band while the hub calibrates this metric (`model.calibrationCaption`).
    private var kpiNormal: (normal: PersonalNormalResult?, sevenDay: Double?) {
        kpiDetailNormal(points: model.history, today: RecoveryInsightService.localDayKey(Date()),
                        hubCalibrating: model.calibrationCaption != nil)
    }

    /// B-57 W3 S2: the metric's 28-day personal normal from the history the chart plots —
    /// fill = the last 7 days, band = your normal, tick = median; "Calibrating" under 14 values.
    private var normalSection: some View {
        let r = kpiNormal
        let unit = model.def.unit.isEmpty ? nil : model.def.unit
        return Surface(level: 1) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last 7 days").jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                    Spacer(minLength: 8)
                    Text(model.calibrationCaption ?? KpiNormal.caption(r.normal, decimals: model.def.decimals)).jiFont(.caption)
                        .foregroundStyle(theme.color(.muted)).multilineTextAlignment(.trailing)
                }
                NormalBar(value: r.sevenDay, normal: r.normal?.range, median: r.normal?.median, unit: unit,
                          decimals: model.def.decimals, tint: metricTintRole(model.metric.rawValue), showsCaption: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("kpi-detail-normal")
    }

    // MARK: - W-GUI R2

    private var kpiDetailValueText: String? {
        model.value.map { formatKpiValue($0, decimals: model.def.decimals) + (model.def.unit.isEmpty ? "" : " \(model.def.unit)") }
    }

    /// W-FIX5 fixer: the Sleep block's Deep + REM (last night only) and the HRV block's SDNN row
    /// (the gate's daytime HRV, the same reading the daytime row above shows).
    private var kpiDetailDeepRem: String? {
        model.metric == .sleep ? kpiDetailDeepRemText(days: model.recovery, now: Date()) : nil
    }
    private var kpiDetailSdnn: String? { model.daytimeHrv == nil ? nil : model.daytimeValueText }

    /// Last night's sleep length from the recovery rows (the same field Recovery's fact tile reads).
    private var kpiDetailSleepDuration: String? {
        guard model.metric == .sleep else { return nil }
        let now = Date()
        for d in model.recovery.sorted(by: { $0.date > $1.date }) {
            if let s = d.sleepDurationSec { return KpiMetrics.isLastNightFresh(nightDate: d.date, now: now) ? recoverySleepDuration(seconds: s) : nil }
        }
        return nil
    }

    private var tableCard: some View {
        let rows = kpiDetailTableRows(history: model.history, value: model.value, unit: model.def.unit, decimals: model.def.decimals,
                                      isNightly: [.hrv, .rhr, .sleep].contains(model.metric), normal: kpiNormal.normal)
        return Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { JIRowDivider().padding(.leading, 0) }
                    HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                            Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        }
                        Spacer(minLength: JISpacing.s2)
                        Text(row.value).jiFont(.body, weight: .semibold)
                            .foregroundStyle(theme.color(row.value.hasPrefix("—") ? .muted : .text))
                            .monospacedDigit().multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, JISpacing.s3)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("kpi-detail-row-\(row.id)")
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
        }
        .accessibilityIdentifier("kpi-detail-table")
    }

    private func blockSection(_ block: KpiDetailBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            JISectionHeader(block.title)
            Surface(level: 1, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { JIRowDivider().padding(.leading, 0) }
                        HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                                Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: JISpacing.s2)
                            Text(row.value).jiFont(.body, weight: .semibold)
                                .foregroundStyle(theme.color(row.value.hasPrefix("—") ? .muted : .text))
                                .multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, JISpacing.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
            }
            Text(block.caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
                .accessibilityIdentifier("kpi-detail-caption")
        }
        .accessibilityIdentifier("kpi-detail-block")
    }
}
