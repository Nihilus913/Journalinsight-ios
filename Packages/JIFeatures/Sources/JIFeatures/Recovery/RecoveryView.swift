import SwiftUI
import JICore
import JICompute
import JIDesign

/// Recovery screen (frozen contract `RecoveryView.init(model:)`). B-57 W1: the v11 board —
/// "Last night" squares (HRV · Sleep · Resting HR · Load) with Edit / hide / reorder, a
/// "+ Add a metric" entry into the KPI catalogue, and HRV over the last 7 nights. Rule 5 (never
/// render a zero for missing data) applies throughout: a missing square is "— No data".
public struct RecoveryView: View {
    @Bindable private var model: RecoveryViewModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen
    @AppStorage("recovery.tileOrder") private var orderRaw = ""
    @AppStorage("recovery.tileHidden") private var hiddenRaw = ""
    @State private var editing = false
    @Environment(\.openKpiCatalogue) private var openKpiCatalogue
    @Environment(\.openKpiDetail) private var openKpiDetail
    @Environment(\.dynamicTypeSize) private var typeSize
    /// B-57 W3: the gate's own Apple-night inputs (HRV / RHR normals, deep sleep); nil = inert.
    @Environment(\.recoveryInsight) private var insight

    public init(model: RecoveryViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                // R-SIM: the navigation subtitle cannot wrap at AX sizes ("28 ni…"); it moves into the page.
                if typeSize.isAccessibilitySize {
                    Text(recoverySubtitle(nights: model.days.count)).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        // §5: the hand-drawn large title becomes the system one; W-GUI R1 (mockup 03): the
        // subtitle says the window, and Edit is a glass round button (report §7 rule 2).
        .navigationTitle("Recovery")
        .navigationSubtitle(typeSize.isAccessibilitySize ? "" : recoverySubtitle(nights: model.days.count))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                JIGlassButton(editing ? "checkmark" : "pencil", label: editing ? "Done" : "Edit") { editing.toggle() }
                    .accessibilityIdentifier("recovery.edit")
            }
        }
        .refreshable { await model.refresh() }
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — mirrors `TodayView.task`.
        .task { if !offscreen, !model.hasLiveResult { await model.load() } }
        .task { if !offscreen { await insight?.refreshIfStale() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var lastNightLabel: some View {
        Text("Last night").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 160); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("recovery.retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let staleDate = staleVerdictBanner {
                // B-46 item 7: the staleness banner used to hug its text and read narrower
                // than every card under it. `Surface` sizes to its content and is frozen, so the
                // width is asserted here, exactly like `StalenessBanner` already does.
                Surface(level: 2) {
                    Text("Showing recovery from \(staleDate) — no newer sync yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityLabel("Showing recovery from \(staleDate) — no newer sync yet.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("recovery.staleBanner")
            }
            // W-FIX4 PF-04: the one rule, not the fetch time; at AX sizes the pill stacks under
            // "Last night" instead of breaking "Synced" mid-word.
            ViewThatFits(in: .horizontal) {
                HStack { lastNightLabel; Spacer(); OneSyncedPill().fixedSize() }
                VStack(alignment: .leading, spacing: 6) { lastNightLabel; OneSyncedPill().fixedSize(horizontal: false, vertical: true) }
            }
            let layout = recoveryTileLayout(orderRaw: orderRaw, hiddenRaw: hiddenRaw)
            if editing {
                // Edit mode keeps the squares' hide / reorder / add-back behaviour (RecoveryTiles prefs).
                SquareGrid(items: recoveryTileItems(days: model.days, layout: layout, editing: editing), editing: editing, columns: recoveryGridColumns,
                           family: .tile,
                           onTap: openKpiDetail.map { open in { id in open(id == "load" ? "acwr" : id) } },
                           onBadge: { id in hiddenRaw = (layout.hidden + [id]).joined(separator: ",") },
                           onMove: { moving, target in orderRaw = squareGridMove(layout.visible + layout.hidden, moving: moving, before: target).joined(separator: ",") },
                           onAdd: layout.hidden.first.map { first in { hiddenRaw = layout.hidden.filter { $0 != first }.joined(separator: ",") } })
            } else {
                // W-GUI R1 (mockup 03): three metric cards (number · "your normal —" · S1 chart), the
                // tinted sleep card with three fact tiles, then "Also watching" tiles of one size.
                ForEach(RecoveryCardMetric.allCases, id: \.rawValue) { metricCard($0) }
                JISectionHeader("Also watching")
                alsoWatching(layout: layout)
                Text(recoveryMonitorCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4)
                    .accessibilityIdentifier("recovery.caption")
            }
        }
    }

    // MARK: - W-GUI R1 cards

    private func metricCard(_ metric: RecoveryCardMetric) -> some View {
        let reading = recoveryCardReading(days: model.days, metric: metric)
        // B-57 W3 S2: the real 28-day normal (the gate's inputs for HRV / RHR); nil = "your normal —".
        let normal = recoveryCardNormal(metric: metric, days: model.days, insightNormal: insightNormal(metric),
                                        today: recoveryToday)
        let tint = metric == .sleep ? theme.color(.sleep) : nil
        return Surface(level: 1, padding: JISpacing.cardPadding, tint: tint) {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                Button { openKpiDetail?(metric.kpiId) } label: {
                    HStack(spacing: JISpacing.s2) {
                        Image(systemName: metric.symbol).foregroundStyle(theme.color(metric.tint)).accessibilityHidden(true)
                        Text(metric.title).jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.color(.mutedNested))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableScale)
                .disabled(openKpiDetail == nil)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(openKpiDetail == nil ? "" : "Opens \(metric.title)")
                .accessibilityIdentifier("recovery.card.\(metric.rawValue)")
                HStack(alignment: .firstTextBaseline, spacing: JISpacing.s2) {
                    Text(jiValueText(reading.value, decimals: metric.decimals))
                        .jiNumeral(.numeralMedium, weight: .heavy, tint: reading.value == nil ? .muted : metric.tint)
                    if reading.value != nil { Text(metric.unit).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                    Spacer(minLength: JISpacing.s2)
                    Text(recoveryNormalText(normal?.range, decimals: metric.decimals)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .multilineTextAlignment(.trailing)
                }
                Text(reading.value == nil ? "— \(JIMissingReason.noData.rawValue)" : (reading.asOf ?? "last night"))
                    .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                if metric == .sleep {
                    HStack(spacing: JISpacing.tileGap) {
                        factTile("Duration", recoverySleepDuration(seconds: recoveryLatestSleepSeconds ?? insightLastNight(.sleepH).map { $0 * 3600 }))
                        factTile("Deep", recoveryDeepText(hours: recoveryDeepHours(insightHours: insightLastNight(.deepH),
                                                                                  days: model.days, now: Date())))
                        factTile("Window", "— not read")
                    }
                } else {
                    NormalBarChart(points: recoveryNights(days: model.days, metric: metric), normal: normal?.range,
                                   unit: metric == .hrv ? "ms" : "bpm", decimals: metric.decimals,
                                   median: normal?.median, tint: metric.tint)
                        .accessibilityIdentifier("recovery.chart.\(metric.rawValue)")
                }
                if metric == .rhr {
                    Text(recoveryRhrCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.metric.\(metric.rawValue)")
    }

    /// The day the normals are for: the insight's loaded day, else the phone's local day.
    private var recoveryToday: String {
        if let day = insight?.today, !day.isEmpty { return day }
        return RecoveryInsightService.localDayKey(Date())
    }

    private func insightNormal(_ metric: RecoveryCardMetric) -> PersonalNormalResult? {
        switch metric {
        case .hrv: insight?.normal(for: .hrv)
        case .rhr: insight?.normal(for: .rhr)
        case .sleep: nil
        }
    }

    /// Last night's value from the gate's inputs (nil = no reading — never a zero).
    private func insightLastNight(_ metric: RecoveryMetric) -> Double? {
        insight?.lastNights(metric, count: 1).last?.value
    }

    /// Last night's sleep length in seconds while it is last night (the squares' rule).
    private var recoveryLatestSleepSeconds: Double? {
        let now = Date()
        for d in model.days.sorted(by: { $0.date > $1.date }) {
            if let s = d.sleepDurationSec { return KpiMetrics.isLastNightFresh(nightDate: d.date, now: now) ? s : nil }
        }
        return nil
    }

    private func factTile(_ label: String, _ value: String) -> some View {
        JITile(family: .factTile) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                Text(value).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(value.hasPrefix("—") ? .muted : .text))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    /// "Also watching": Load (from the squares' items, only while it is visible), then W-DATA's
    /// resp rate / wrist temp / body battery / recovery time from `/vitals/recovery` — dated, or
    /// "—" + a reason word (`recoveryWatchReadings`) — and Add a metric, all `.tile`.
    private func alsoWatching(layout: RecoveryTileLayout) -> some View {
        let items = recoveryTileItems(days: model.days, layout: layout, editing: false).filter { $0.id == "load" }
        // W-DATA fixer R9: no hub ACWR (Apple never sends one) → the gate-input load with its band.
        let load = items.first?.value == nil ? insight?.loadReading : nil
        return Columns(minimum: 100, spacing: JISpacing.tileGap, tileHeight: .tile) {
            ForEach(items) { item in
                Button { openKpiDetail?("acwr") } label: {
                    JITile(family: .tile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            Text(load?.valueText ?? jiValueText(item.value, decimals: item.decimals))
                                .jiNumeral(.numeralSmall, tint: item.value == nil && load == nil ? .muted : item.tint)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(load?.caption ?? item.goalText ?? item.status?.word ?? "").jiFont(.micro).foregroundStyle(theme.color(.muted))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                .buttonStyle(.pressableScale)
                .disabled(openKpiDetail == nil)
                .accessibilityLabel(load.map(\.accessibilityText) ?? squareAccessibilityLabel(item))
                .accessibilityIdentifier("recovery.watch.\(item.id)")
            }
            ForEach(recoveryWatchReadings(days: model.days, today: recoveryToday), id: \.id) { watchTile($0) }
            if let openKpiCatalogue {
                JIAddTile(family: .tile, label: "Add a metric") { openKpiCatalogue() }
                    .accessibilityIdentifier("recovery.addMetric")
            }
        }
    }

    private func watchTile(_ reading: RecoveryWatchReading) -> some View {
        JITile(family: .tile) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                Text(reading.value).jiNumeral(.numeralSmall, tint: reading.missing ? .muted : .text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(reading.caption).jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reading.missing ? "\(reading.label), \(reading.caption)" : "\(reading.label) \(reading.value), \(reading.caption)")
        .accessibilityIdentifier("recovery.watch.\(reading.id)")
    }

    private var staleVerdictBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}

/// B-57 W3 S2: a Recovery card's band. HRV / RHR use the gate's own normal (the Apple-night
/// inputs, 42 days) when it exists, else the normal of the nights the card plots; the sleep card
/// plots the sleep score, so only a score normal fits it. nil = "your normal —" (Calibrating).
public nonisolated func recoveryCardNormal(metric: RecoveryCardMetric, days: [RecoveryDay],
                                           insightNormal: PersonalNormalResult?, today: String) -> PersonalNormalResult? {
    if metric != .sleep, let insightNormal { return insightNormal }
    return KpiNormal.make(points: days.map { (date: $0.date, value: metric.value($0)) }, today: today).normal
}

/// B-57 W3: the "Deep" fact tile from the gate's deep-sleep hours; "— not read" without a reading.
public nonisolated func recoveryDeepText(hours: Double?) -> String {
    recoverySleepDuration(seconds: hours.map { $0 * 3600 })
}

/// The hub's `YYYY-MM-DD` day string as a chart x-value. UTC on purpose — a day string has no
/// time zone, and `TrendChart` only ever orders and labels these.
public nonisolated func recoveryTrendDate(_ day: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
    var c = calendar
    c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

// MARK: - W-DATA R4 / R6: "Also watching" readings

/// One "Also watching" tile: `value` is the number as shown, or "—" with the reason in `caption`.
public nonisolated struct RecoveryWatchReading: Equatable, Sendable {
    public let id: String, label: String, value: String, caption: String
    public var missing: Bool { value == "—" }
}

/// Apple's Vitals app needs about five nights for a wrist-temperature baseline (the hub's
/// `WRIST_TEMP_MIN_BASELINE_NIGHTS`); below that the tile says "Calibrating · n of 5 nights".
public nonisolated let recoveryWristTempBaselineNights = 5

/// W-DATA R4 / R6: resp rate (last night's `resp_sleep_avg`), wrist temp (deviation from the
/// user's own baseline — never the absolute sensor value, never a clinical reading), Garmin body
/// battery low–high and recovery time. Each is the newest night that has it, named by its night
/// ("last night" for the wake day `today`, else "as of Sep 25"); none = "—" · "not read".
public nonisolated func recoveryWatchReadings(days: [RecoveryDay], today: String) -> [RecoveryWatchReading] {
    let newestFirst = days.sorted { $0.date > $1.date }
    func newest(_ has: (RecoveryDay) -> Bool) -> RecoveryDay? { newestFirst.first(where: has) }
    func night(_ day: RecoveryDay) -> String {
        kpiAsOfLabel(valueDate: day.date, today: today) ?? "last night"
    }
    func notRead(_ id: String, _ label: String) -> RecoveryWatchReading {
        RecoveryWatchReading(id: id, label: label, value: "—", caption: "not read")
    }

    let resp: RecoveryWatchReading = newest { $0.respSleepAvg != nil }.map {
        RecoveryWatchReading(id: "resp", label: "Resp. rate", value: jiNumber($0.respSleepAvg ?? 0, 1), caption: "br/min · \(night($0))")
    } ?? notRead("resp", "Resp. rate")

    let temp: RecoveryWatchReading
    if let d = newest({ $0.wristTempC != nil }) {
        if let dev = d.wristTempDevC {
            let text = jiNumber(abs(dev), 1)
            let sign = text == jiNumber(0, 1) ? "±" : (dev > 0 ? "+" : "−")
            temp = RecoveryWatchReading(id: "wristTemp", label: "Wrist temp", value: sign + text + "°", caption: "vs normal · \(night(d))")
        } else {
            let n = Int(d.wristTempBaselineNights ?? 0)
            temp = RecoveryWatchReading(id: "wristTemp", label: "Wrist temp", value: "—",
                                        caption: "\(JIMissingReason.calibrating.rawValue) · \(n) of \(recoveryWristTempBaselineNights) nights")
        }
    } else {
        temp = notRead("wristTemp", "Wrist temp")
    }

    let battery: RecoveryWatchReading = newest { $0.bodyBatteryMin != nil && $0.bodyBatteryMax != nil }.map {
        RecoveryWatchReading(id: "bodyBattery", label: "Body Battery",
                             value: "\(jiNumber($0.bodyBatteryMin ?? 0, 0))–\(jiNumber($0.bodyBatteryMax ?? 0, 0))",
                             caption: "low–high · \(night($0))")
    } ?? notRead("bodyBattery", "Body Battery")

    let recoveryTime: RecoveryWatchReading = newest { $0.recoveryTimeMin != nil }.map {
        let m = Int(($0.recoveryTimeMin ?? 0).rounded())
        let text = m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))"
        return RecoveryWatchReading(id: "recoveryTime", label: "Recovery time", value: text, caption: "to recover · \(night($0))")
    } ?? notRead("recoveryTime", "Recovery time")

    return [resp, temp, battery, recoveryTime]
}

/// W-DATA R6: the Deep fact tile's hours — the gate's own deep-sleep reading, else the route's
/// `deep_sleep_sec` for last night only (the ≤ 36 h "last night" rule); nil = "— not read".
public nonisolated func recoveryDeepHours(insightHours: Double?, days: [RecoveryDay], now: Date) -> Double? {
    if let insightHours { return insightHours }
    guard let d = days.sorted(by: { $0.date > $1.date }).first(where: { $0.deepSleepSec != nil }),
          KpiMetrics.isLastNightFresh(nightDate: d.date, now: now), let sec = d.deepSleepSec else { return nil }
    return sec / 3600
}
