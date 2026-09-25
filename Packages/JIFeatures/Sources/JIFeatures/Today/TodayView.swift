import SwiftUI
import JICore
import JIDesign

public struct TodayView: View {
    @Bindable private var model: TodayViewModel
    private let onOpenConnection: () -> Void
    private let onSelectKpi: (String) -> Void
    /// W5b-L4 (P-gate-respond) close-out wiring: builds the gate answer card's model for the loaded
    /// gate's recommendation (the App supplies outbox + decision log); `nil` = no card, as before.
    private let makeGateRespondModel: (GateRecommendation) -> GateRespondViewModel?
    @State private var gateRespondModel: GateRespondViewModel?
    /// B-57 §6/§9: the Day summary line re-opens this morning's Coach overlay, read-only.
    @State private var showMorningReview = false
    /// W-B57b (B-62): Decide's Go / Adjust write, built by the App (nil = Go just advances).
    @Environment(\.verdictOverrideModel) private var verdictOverrideModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch and no model rebuild while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(model: TodayViewModel, onOpenConnection: @escaping () -> Void, onSelectKpi: @escaping (String) -> Void = { _ in },
                makeGateRespondModel: @escaping (GateRecommendation) -> GateRespondViewModel? = { _ in nil }) {
        self.model = model; self.onOpenConnection = onOpenConnection; self.onSelectKpi = onSelectKpi
        self.makeGateRespondModel = makeGateRespondModel
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded:
                    // B-57 §2: Decide → Coach → Day, advanced only by what the user does and kept
                    // per verdict date (`TodayViewModel.morningState`).
                    switch model.morningState {
                    case .decide:
                        DecideView(verdict: model.verdict, readiness: model.readiness,
                                   syncing: model.morning?.verdict == nil,
                                   gateSignals: model.morning?.gateSignals,
                                   verdictDate: model.verdictDate,
                                   sessionForToday: model.morning?.sessionForToday,
                                   override: currentOverride,
                                   overrideModel: verdictOverrideModel,
                                   fetchedAt: model.fetchedAt) { model.morningEvent(.gateResponded) }
                    case .coach, .day:
                        // §9: Coach is the Day view plus a bottom overlay card (below), not a step.
                        dayContent
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .refreshable { JIHaptic.fire(.selection); await model.refresh() }   // W8-L1 (P-haptics) — oracle SyncButton.tsx:136 hapticSelection() the instant the sync is kicked off (Swift sync control = pull-to-refresh)
        // §5: the hand-drawn large title becomes the system one; the date line is the subtitle.
        .navigationTitle(loadTodayPageName(prefs: model.tileOrderStore))
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — a cancelled fetch over a warm cache
        // leaves `phase == .loaded` (restored from cache), so keying off `.idle` alone would never
        // re-fetch live data on the next appearance.
        .task { if !offscreen, !model.hasLiveResult { await model.load() } }
        // One respond model per recommendation: rebuilt only when the loaded gate's answer changes,
        // never per body evaluation (the model carries in-flight/pending state).
        .onChange(of: model.gate?.recommendation, initial: !offscreen) { _, recommendation in
            gateRespondModel = recommendation.flatMap(makeGateRespondModel)
        }
        .animation(JIMotion.standard, value: model.phase)
        .animation(JIMotion.standard, value: model.morningState)
        // §9 Coach overlay: in the morning flow ✕ / swipe-down = `coachAcknowledged`; re-opened
        // from the summary line it is read-only (dismiss only closes it, nothing advances).
        .overlay(alignment: .bottom) {
            if model.phase == .loaded, model.morningState == .coach || showMorningReview {
                CoachOverlayCard(change: coachContent.change) {
                    if model.morningState == .coach { model.morningEvent(.coachAcknowledged) }
                    showMorningReview = false
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
                .readableColumn()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(JIMotion.standard, value: showMorningReview)
        .environment(\.gateRespondModel, gateRespondModel)
        .onChange(of: model.morning?.verdictOverride, initial: true) { _, fresh in
            // A fresher `/morning` re-seeds the device's view of the call — except while this
            // device's own write is only queued and the hub has not seen it yet.
            guard let verdictOverrideModel else { return }
            if fresh != nil || verdictOverrideModel.phase != .queued { verdictOverrideModel.seed(fresh) }
        }
    }

    /// W-B57b (B-62): the call in effect for the verdict date — this device's latest write, else
    /// the hub's row from `/morning`.
    private var currentOverride: VerdictOverride? {
        overrideForVerdictDate(verdictOverrideModel?.current ?? model.morning?.verdictOverride, verdictDate: model.verdictDate)
    }

    /// The verdict as the user decided it (`effectiveVerdict`) — what Day and the summary line show.
    private var shownVerdict: VerdictParts { effectiveVerdictParts(parts: model.verdict, override: currentOverride) }

    @ViewBuilder
    private var dayContent: some View {
        // W-FIX2 DEV-03: the newer of the hub's last sync and this app's last 2xx HealthKit upload.
        HStack { Spacer(); SyncedPill(date: model.syncedAt) }.accessibilityIdentifier("today.day.synced")
        MorningSummaryLine(verdict: shownVerdict, readiness: model.readiness,
                           caption: currentOverride.flatMap { effectiveVerdict(parts: model.verdict, override: $0).wasCaption }) {
            showMorningReview = true
        }
        // §8.1: hero + drivers compose side by side in regular width and stack in compact.
        // readinessMissing: false — W1 has only the hub provider, which always carries a
        // readiness field (nil when the hub itself has no score yet); a real "source doesn't
        // support this metric" case awaits W2+'s additional providers.
        AdaptiveHStack {
            VerdictHeroView(verdict: shownVerdict, readiness: model.readiness, readinessMissing: false,
                            sleepScore: chip("sleep")?.value, load: latestAcwr,
                            insight: InsightSentence.build(gate: model.gate, morning: model.morning),
                            gateRespondModel: gateRespondModel, showsRespondRow: false)
            ringsRow
        }
        TodayGrid(chips: model.chips, prefs: model.tileOrderStore, onSelectKpi: onSelectKpi)
        // B-57 W1: the Trends card became a full screen, reached from this footer link.
        HStack {
            Spacer()
            NavigationLink {
                TrendsView(recovery: model.recovery, daily: model.gate?.daily ?? [], averages: model.gate?.averages, onSelectKpi: onSelectKpi)
            } label: {
                Text("Trends").jiFont(.subheadline, weight: .semibold).underline().foregroundStyle(theme.color(.info))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.pressableScale)
            .accessibilityIdentifier("today.footer.trends")
        }
        // Room so the Coach overlay never covers the last card.
        if model.morningState == .coach || showMorningReview { Color.clear.frame(height: 140).accessibilityHidden(true) }
    }

    /// B-57 §9 Coach: the one change for today, built from the DTOs this screen already holds.
    private var coachContent: CoachContent {
        CoachContentBuilder.build(morning: model.morning, gate: model.gate, recovery: model.recovery)
    }

    /// §4b + B-42: the hero's ring trio, then exactly two small rings — no longer hard-wired to
    /// Sleep/Steps but the user's own first two "My KPIs" (`KpiSelection`, the same `PrefStore`
    /// selection the KPI list writes), with live values.
    ///
    /// A KPI with no bounded scale (HRV, RHR, ACWR, weight, macros — §4b: never a ring, they are
    /// baseline-relative) renders as a value tile instead of a ring, rather than being forced onto
    /// an invented 0–100 axis.
    @ViewBuilder
    private var ringsRow: some View {
        Surface(level: 1) {
            // A ring pair is fixed-width art: `Columns` drops it to one-up at AX sizes rather than
            // pushing the composition wider (§8.1 "reflows, never clips").
            Columns(minimum: 96, spacing: 16) {
                ForEach(myKpis, id: \.self) { id in
                    let def = KpiMetrics.def(id)
                    let latest = kpiLatest(id)
                    kpiCell(def: def, value: latest?.value,
                            asOf: kpiAsOfLabel(valueDate: latest?.date, today: todayDateString))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The first two selected "My KPIs", in the user's own rank order. Falls back to the default
    /// selection when nothing is persisted yet (or no `PrefStore` is wired at this call site).
    private var myKpis: [KpiMetricId] {
        let saved = (try? model.tileOrderStore?.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)) ?? nil
        return Array(KpiSelection.visibleOrder(KpiSelection.reconcile(saved)).prefix(2))
    }

    /// Live value for a KPI, from the sections Today already holds. Nutrition-sourced KPIs
    /// (kcal/protein/carbs/fat) read `[]` here — this screen never fetches the nutrition week —
    /// so they show their "No data yet" state rather than a stale number.
    private func kpiValue(_ id: KpiMetricId) -> Double? { kpiLatest(id)?.value }

    /// B-46 item 3 (fixer): the value AND the day it was actually taken on, so a week-old HRV is
    /// never presented as today's reading (the same `KpiMetrics.latest` the KPI detail screen uses).
    /// W-FIX2 DEV-01/02: read through the view model (`kpiReading`) so the cell and the hero agree.
    private func kpiLatest(_ id: KpiMetricId) -> (value: Double, date: String)? { model.kpiReading(id) }

    private var todayDateString: String { String(Date().ISO8601Format().prefix(10)) }

    private func chip(_ id: String) -> TodayChip? { model.chips.first { $0.id == id } }

    /// The hero trio's Load ring: the current ACWR or "—" (W-FIX1 BUG-12, `TodayViewModel.heroLoad`).
    private var latestAcwr: Double? { model.heroLoad }

    @ViewBuilder
    private func kpiCell(def: KpiMetricDef, value: Double?, asOf: String? = nil) -> some View {
        Button { onSelectKpi(def.id.rawValue) } label: {
            VStack(spacing: 6) {
                if let max = todayKpiRingMax(def.id) {
                    if let value {
                        ScoreRing(value: value, max: max, tint: theme.color(todayKpiRingRole(def.id)))
                    } else {
                        // Rule 5: never a zero ring for missing data.
                        ScoreRing(value: 0, max: max, tint: theme.color(.nested)).accessibilityHidden(true)
                    }
                }
                Text(def.label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(def.decimals))) } ?? "No data yet")
                        .jiFont(.footnote, weight: .semibold)
                        .foregroundStyle(value == nil ? theme.color(.muted) : theme.color(.text))
                    if value != nil, !def.unit.isEmpty {
                        Text(def.unit).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                // B-46 item 3: a fallback reading names its own day — never silently "today".
                if let asOf {
                    Text(asOf).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("today.kpiRing.\(def.id.rawValue).as-of")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressableScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todayKpiCellAccessibilityLabel(label: def.label, value: value, decimals: def.decimals, unit: def.unit, asOf: asOf))
        .accessibilityIdentifier("today.kpiRing.\(def.id.rawValue)")
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 44); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                HStack {
                    Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                        .accessibilityLabel("Retry")
                        .accessibilityIdentifier("today.retry")
                    Button("Connection…", action: onOpenConnection).buttonStyle(.pressableScale).tint(theme.color(.info))
                        .accessibilityLabel("Connection…")
                        .accessibilityIdentifier("today.connection")
                }
            }
        }
    }
}

/// §4b: a Today ring is only ever drawn for a metric with a real, bounded scale — a 0–100 score or
/// a count against a goal. Everything else (HRV, RHR, ACWR, weight, macros) is baseline-relative
/// and stays a number, never a ring. `nil` = "no ring for this KPI".
public nonisolated func todayKpiRingMax(_ id: KpiMetricId) -> Double? {
    switch id {
    case .sleep, .readiness, .bodyBattery: 100
    case .steps: todayStepsGoal
    case .hrv, .rhr, .acwr, .weight, .kcal, .protein, .carbs, .fat: nil
    }
}

/// The ring tint per KPI — inside the non-reserved set (rule 6 keeps go/danger for the verdict).
public nonisolated func todayKpiRingRole(_ id: KpiMetricId) -> JIColorRole {
    switch id {
    case .sleep: .sleep
    case .steps: .info
    default: .reduced
    }
}

/// §4b: Steps is a bounded ring only against a goal. The hub carries no per-day step goal yet, so
/// the ring uses the oracle's default target; a hub-supplied goal replaces this constant when one
/// lands (P-goals).
public nonisolated let todayStepsGoal: Double = 8_000

/// The number under a Today ring — a whole, grouped figure (a 0–100 score or a step count).
public nonisolated func todayRingValueText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}


/// B-46 item 3 (fixer): the My-KPI cell's VoiceOver sentence, pure so a host test can assert the
/// as-of day is announced and not merely computed.
nonisolated func todayKpiCellAccessibilityLabel(label: String, value: Double?, decimals: Int, unit: String, asOf: String?) -> String {
    guard let value else { return "\(label), no data yet" }
    let number = value.formatted(.number.precision(.fractionLength(decimals)))
    return [label, number, unit.isEmpty ? nil : unit, asOf].compactMap { $0 }.joined(separator: " ")
}
