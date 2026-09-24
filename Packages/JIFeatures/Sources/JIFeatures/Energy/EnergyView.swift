import SwiftUI
import JICore
import JIDesign

/// B-57 W1: the board's subtitle and "What you burn" copy (W1 ships the wording; the values stay
/// hub-sourced until W2's HealthKit reads, so the burn card shows "Not in Health yet").
public nonisolated let energySubtitle = "What you eat against what you burn, from Apple Health"
public nonisolated let energyBurnCardCopy = "Resting plus active energy, both read from Apple Health. JI adds them up each day."

/// Energy tab (W3a-L1, frozen contract `EnergyView.init(model:)` for `RootTabView`'s L4 wiring).
/// Composes `EnergyHero` + `IntakeTdeeChart` + `DeficitDayList` from `RecoveryView`'s own
/// loading/error/empty/loaded phase switch (the pattern the wave card names) — single-column only
/// this wave; the RN oracle's >=600dp two-pane layout is left for a follow-up (out of this lane's
/// exit criteria, which cover render-from-fixture + states, not window-size adaptivity).
public struct EnergyView: View {
    @Bindable private var model: EnergyViewModel
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native
    /// §2b.3 Health range picker over the balance trend.
    @State private var range: TrendRange = .month

    public init(model: EnergyViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        // §5: the hand-drawn large title becomes the system one.
        .navigationTitle("Energy")
        #if os(iOS)
        .navigationSubtitle(energySubtitle)
        #endif
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 150); SkeletonBlock(height: 320) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("energy.retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Spacer(); SyncedPill(date: model.fetchedAt, label: .lastSynced) }
            if let staleDate = staleDateBanner {
                Surface(level: 2) {
                    Text("Showing energy from \(staleDate) — no newer sync yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityLabel("Showing energy from \(staleDate) — no newer sync yet.")
                }
            }
            if let report = model.report {
                JISectionHeader("Balance")
                // §8.1: hero and trend compose side by side in regular width, stack on a phone.
                AdaptiveHStack {
                    EnergyHero(report: report)
                    Surface(padding: 18) {
                        // §2b.3: the Health range picker + dashed average, over the daily balance
                        // (`-deficit`, the sign people read). §4b: no arc — energy balance is
                        // signed and unbounded, so it is a line, never a ring.
                        TrendChart(points: balancePoints(report.days), tint: theme.color(.info),
                                   unit: "kcal", range: $range, showAll: nil)
                            .accessibilityIdentifier("energy.balanceTrend")
                    }
                }
                HowWeCalculateLink(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
                HStack(alignment: .firstTextBaseline) {
                    Text("What you burn").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("7-day average").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
                Surface(level: 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("—").jiNumeral(.numeralMedium, tint: .muted)
                            Label(JIMissingReason.notInHealthYet.rawValue, systemImage: "minus").jiFont(.subheadline, weight: .semibold)
                                .foregroundStyle(theme.color(.muted))
                        }
                        Text(energyBurnCardCopy).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("energy.whatYouBurn")
                }
                HowWeCalculate(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
                    .accessibilityIdentifier("energy.howWeCalculate")
                JISectionHeader("Intake vs TDEE")
                Surface(padding: 18) {
                    IntakeTdeeChart(days: report.days)
                        .accessibilityIdentifier("energy.intakeTdeeChart")
                }
            }
            JISectionHeader("Daily log")
            Surface(padding: 18) {
                DeficitDayList(days: model.days)
                    .accessibilityIdentifier("energy.dailyLog")
            }
        }
    }

    /// The balance series the range picker filters: `-deficit` per day, newest `range.days` days,
    /// untracked days omitted rather than drawn as a zero (rule 5).
    private func balancePoints(_ days: [EnergyDay]) -> [TrendPoint] {
        days.sorted { $0.date < $1.date }
            .suffix(range.days)
            .compactMap { day in
                guard let deficit = day.deficitCorrected, !deficit.isNaN,
                      let date = trainingStripDate(day.date) else { return nil }
                return TrendPoint(date: date, value: -deficit)
            }
    }

    private var staleDateBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}
