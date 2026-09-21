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
                    // §8.1: hero + drivers compose side by side in regular width and stack in compact.
                    // readinessMissing: false — W1 has only the hub provider, which always carries a
                    // readiness field (nil when the hub itself has no score yet); a real "source doesn't
                    // support this metric" case awaits W2+'s additional providers.
                    AdaptiveHStack {
                        VerdictHeroView(verdict: model.verdict, readiness: model.readiness, readinessMissing: false, gateRespondModel: gateRespondModel)
                        ringsRow
                    }
                    TodayGrid(chips: model.chips, prefs: model.tileOrderStore, onSelectKpi: onSelectKpi)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .refreshable { JIHaptic.fire(.selection); await model.refresh() }   // W8-L1 (P-haptics) — oracle SyncButton.tsx:136 hapticSelection() the instant the sync is kicked off (Swift sync control = pull-to-refresh)
        // §5: the hand-drawn large title becomes the system one; the date line is the subtitle.
        .navigationTitle("Today")
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
    }

    /// §4b: Today gets the hero arc plus exactly two small rings — Sleep score (0–100) and Steps
    /// against the day's goal. Never HRV / RHR / ACWR (baseline-relative; they stay chips).
    @ViewBuilder
    private var ringsRow: some View {
        let sleep = model.chips.first { $0.id == "sleep" }
        let steps = model.chips.first { $0.id == "steps" }
        Surface(level: 1) {
            // A ring pair is fixed-width art: `Columns` drops it to one-up at AX sizes rather than
            // pushing the composition wider (§8.1 "reflows, never clips").
            Columns(minimum: 96, spacing: 16) {
                ring(label: "Sleep", value: sleep?.value, max: 100, tint: theme.color(.sleep), sourceMissing: sleep?.sourceMissing ?? false)
                ring(label: "Steps", value: steps?.value, max: todayStepsGoal, tint: theme.color(.reduced), sourceMissing: steps?.sourceMissing ?? false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func ring(label: String, value: Double?, max: Double, tint: Color, sourceMissing: Bool) -> some View {
        VStack(spacing: 6) {
            if let value, !sourceMissing {
                ScoreRing(value: value, max: max, tint: tint)
            } else {
                // Rule 5: never a zero ring for missing data.
                ScoreRing(value: 0, max: max, tint: theme.color(.nested))
                    .accessibilityHidden(true)
            }
            Text(label).jiFont(.caption).foregroundStyle(theme.color(.muted))
            Text(value.map { todayRingValueText($0) } ?? "No data yet")
                .jiFont(.footnote, weight: .semibold)
                .foregroundStyle(value == nil ? theme.color(.muted) : theme.color(.text))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(label) \(todayRingValueText($0))" } ?? "\(label), no data yet")
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

/// §4b: Steps is a bounded ring only against a goal. The hub carries no per-day step goal yet, so
/// the ring uses the oracle's default target; a hub-supplied goal replaces this constant when one
/// lands (P-goals).
public nonisolated let todayStepsGoal: Double = 8_000

/// The number under a Today ring — a whole, grouped figure (a 0–100 score or a step count).
public nonisolated func todayRingValueText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}
