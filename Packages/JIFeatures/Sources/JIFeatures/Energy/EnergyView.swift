import SwiftUI
import JICore
import JIDesign

/// B-57 W1: the board's subtitle and "What you burn" copy (W1 ships the wording; the values stay
/// hub-sourced until W2's HealthKit reads, so the burn card shows "Not in Health yet").
public nonisolated let energySubtitle = "What you eat against what you burn, from Apple Health"
public nonisolated let energyBurnCardCopy = "Resting plus active energy, both read from Apple Health. JI adds them up each day."

/// Energy tab (W3a-L1, frozen contract `EnergyView.init(model:)` for `RootTabView`'s L4 wiring).
/// Composes `EnergyHero` + "This week" (`EnergyWeekChart`) + the Daily log (`DeficitDayList`)
/// from `RecoveryView`'s own
/// loading/error/empty/loaded phase switch (the pattern the wave card names) — single-column only
/// this wave; the RN oracle's >=600dp two-pane layout is left for a follow-up (out of this lane's
/// exit criteria, which cover render-from-fixture + states, not window-size adaptivity).
public struct EnergyView: View {
    @Bindable private var model: EnergyViewModel
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

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
            EnergySections(report: model.report, days: model.days, goal: model.goalKcal, today: today)
        }
    }

    private var today: String { energyTodayISO(model.now()) }

    private var staleDateBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}

/// B-57 W1 r5: the board's sections in order — hero, "How we calculate this", What you burn,
/// How we calculate (with the no-medical-judgement note), This week, Daily log. `EnergyView` and
/// the registry preview (`EnergyNativePreview`) both render THIS view, so the sweep shows the
/// same sections the screen does.
struct EnergySections: View {
    let report: EnergyReport?
    let days: [EnergyDay]
    let goal: Double?
    let today: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report {
                // B-57 W1 r4: the board has no balance trend chart and no "Intake vs TDEE".
                EnergyHero(report: report, goal: goal)
                HowWeCalculateLink(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
                EnergyBurnCard()
                HowWeCalculate(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
                    .accessibilityIdentifier("energy.howWeCalculate")
                EnergyThisWeek(days: report.days, goal: goal, today: today)
            }
            JISectionHeader("Daily log")
            Surface(padding: 18) {
                DeficitDayList(days: days, goal: goal, today: today)
                    .accessibilityIdentifier("energy.dailyLog")
            }
        }
    }
}

/// Board "What you burn": the words ship in W1; resting + active energy from HealthKit arrive in
/// W2 (the resting / active split is left for W2 too), so the value is "— Not in Health yet".
struct EnergyBurnCard: View {
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { burnTitle.fixedSize(); Spacer(minLength: 8); burnAside.fixedSize() }
                VStack(alignment: .leading, spacing: 2) {
                    burnTitle.fixedSize(horizontal: false, vertical: true); burnAside.fixedSize(horizontal: false, vertical: true)
                }
            }
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: 8) {
                    // AX3: the reason takes its own line rather than truncating.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) { burnDash; burnReason.fixedSize() }
                        VStack(alignment: .leading, spacing: 4) { burnDash; burnReason.fixedSize(horizontal: false, vertical: true) }
                    }
                    Text(energyBurnCardCopy).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("energy.whatYouBurn")
            }
        }
    }

    private var burnTitle: some View {
        Text("What you burn").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
    }
    private var burnAside: some View { Text("7-day average").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
    private var burnDash: some View { Text("—").jiNumeral(.numeralMedium, tint: .muted) }
    private var burnReason: some View {
        Text(JIMissingReason.notInHealthYet.rawValue).jiFont(.subheadline, weight: .semibold)
            .foregroundStyle(theme.color(.muted))
    }
}

/// Board "This week": header with the user's goal, the bars, and the "still filling in" caption.
/// The board's Week / 30 D / 90 D picker is left out: the screen loads 7 days, and a picker that
/// could not change what is shown would be a fake control.
struct EnergyThisWeek: View {
    let days: [EnergyDay]
    let goal: Double?
    let today: String
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // AX3: "This week" and the goal stack instead of truncating.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { weekTitle.fixedSize(); Spacer(minLength: 8); goalText.fixedSize() }
                VStack(alignment: .leading, spacing: 2) {
                    weekTitle.fixedSize(horizontal: false, vertical: true); goalText.fixedSize(horizontal: false, vertical: true)
                }
            }
            Surface(padding: 16) {
                EnergyWeekChart(bars: energyWeekBars(days: days, today: today), goal: goal)
            }
            if let caption = energyFillingInCaption(days: days, today: today) {
                Text(caption).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy.fillingIn")
            }
        }
    }

    private var weekTitle: some View {
        Text("This week").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
    }
    private var goalText: some View {
        Text(energyGoalHeaderText(goal)).jiFont(.footnote, weight: .semibold)
            .foregroundStyle(theme.color(goal == nil ? .muted : .text))
            .accessibilityIdentifier("energy.goal")
    }
}

/// "Goal 1617 kcal", or "No goal set".
public nonisolated func energyGoalHeaderText(_ goal: Double?) -> String {
    guard let goal, goal.isFinite else { return EnergyDayStatus.noGoal.word }
    return "Goal \(jiNumber(goal, 0)) kcal"
}
