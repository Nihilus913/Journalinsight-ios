import SwiftUI
import JICore
import JICompute
import JIDesign

/// B-57 W1: the board's subtitle and "What you burn" copy. W-FIX3 BUG-38: the burn value is the
/// hub's measured per-day burn (`tdee_raw`), averaged over the last 7 complete days.
public nonisolated let energySubtitle = "What you eat against what you burn, from Apple Health"
public nonisolated let energyBurnCardCopy = "Resting plus active energy, both read from Apple Health. JI adds them up each day."

/// W-FIX4 PF-09: Energy's "How we calculate" with the true intake lineage — eaten comes from the
/// YAZIO API (the hub's `core.nutrition_daily`), not from dietary energy in Apple Health. The
/// burn step is the shared `JIExplainers` copy unchanged. B-57 W2 (B-73): the band step is the
/// user's own target ± 100 (`EnergyBandCopy.bandRuleStep`), never a JI-picked number.
public nonisolated let energyHowWeCalculateSteps: [HowWeCalculateStep] = {
    var steps = JIExplainers.energyBalanceSteps
    steps[1] = HowWeCalculateStep(title: "Eaten = your YAZIO day total",
                                  body: "The hub reads it from YAZIO each sync. JI only reads the day total; it never logs food.")
    steps[2] = HowWeCalculateStep(title: steps[2].title,
                                  body: "Averaged over the last 7 complete days. Today counts once it ends. A day with no food logged in YAZIO is skipped, not counted as zero.")
    steps[3] = EnergyBandCopy.bandRuleStep
    return steps
}()

/// Energy tab (W3a-L1, frozen contract `EnergyView.init(model:)` for `RootTabView`'s L4 wiring).
/// Composes `EnergyHero` + "This week" (`EnergyWeekChart`) + the Daily log (`DeficitDayList`)
/// from `RecoveryView`'s own
/// loading/error/empty/loaded phase switch (the pattern the wave card names) — single-column only
/// this wave; the RN oracle's >=600dp two-pane layout is left for a follow-up (out of this lane's
/// exit criteria, which cover render-from-fixture + states, not window-size adaptivity).
public struct EnergyView: View {
    @Bindable private var model: EnergyViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: EnergyViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // W-FIX3 BUG-33: at AX sizes the navigation subtitle truncates; it moves into the
                // page as wrapping text instead.
                if typeSize.isAccessibilitySize {
                    Text(energySubtitle).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("energy.subtitle")
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
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        // §5: the hand-drawn large title becomes the system one.
        .navigationTitle("Energy")
        #if os(iOS)
        .navigationSubtitle(typeSize.isAccessibilitySize ? "" : energySubtitle)
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
            HStack { Spacer(); OneSyncedPill(label: .lastSynced) }  // W-FIX4 PF-04
            if let staleDate = staleDateBanner {
                Surface(level: 2) {
                    Text("Showing energy from \(staleDate) — no newer sync yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityLabel("Showing energy from \(staleDate) — no newer sync yet.")
                }
            }
            EnergySections(report: model.report, days: model.days, goal: model.goalKcal, today: today, band: model.bandState)
        }
    }

    private var today: String { energyTodayISO(model.now()) }

    private var staleDateBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}

/// The board's sections above the Daily log, in order. W-FIX3 BUG-39: "How we calculate" once
/// (the old link row repeated the same explainer right above the full card).
nonisolated enum EnergySection: CaseIterable, Equatable, Sendable {
    case hero, whatYouBurn, howWeCalculate, thisWeek
}

/// B-57 W1 r5: the board's sections in order — hero, What you burn, How we calculate (with the
/// no-medical-judgement note), This week, Daily log. `EnergyView` and
/// the registry preview (`EnergyNativePreview`) both render THIS view, so the sweep shows the
/// same sections the screen does.
struct EnergySections: View {
    let report: EnergyReport?
    let days: [EnergyDay]
    let goal: Double?
    let today: String
    /// B-73: the phone's band (user target ± 100, Health burn). `.none` = hub report path only.
    var band: EnergyBandState = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report {
                // B-57 W1 r4: the board has no balance trend chart and no "Intake vs TDEE".
                ForEach(EnergySection.allCases, id: \.self) { section in
                    switch section {
                    case .hero: EnergyHero(report: report, goal: goal, band: band)
                    case .whatYouBurn: EnergyBurnCard(days: report.days, today: today, window: band.burn, reason: band.reason)
                    case .howWeCalculate:
                        HowWeCalculate(title: JIExplainers.energyBalanceTitle, steps: energyHowWeCalculateSteps, note: JIExplainers.energyBalanceNote)
                            .accessibilityIdentifier("energy.howWeCalculate")
                        EnergyBandDisclaimers(burn: band.burn)
                    case .thisWeek: EnergyThisWeek(days: report.days, goal: goal, today: today)
                    }
                }
            }
            JISectionHeader("Daily log")
            Surface(padding: 18) {
                DeficitDayList(days: days, goal: goal, today: today)
                    .accessibilityIdentifier("energy.dailyLog")
            }
        }
    }
}

/// Board "What you burn": B-73 the 7-day Apple Health burn (resting + active, source-merged) with
/// its split; without it, "—" plus the true reason word ("Not in Health yet", "Calibrating").
/// fixer2 BUG-38/RF2-BURN: the card's copy names Apple Health, so its one number is the Health
/// burn only — the hub's `tdee_raw` average never stands in under that copy (it disagreed with the
/// hero's route expenditure: two burn numbers, one false source line).
struct EnergyBurnCard: View {
    var days: [EnergyDay] = []
    var today: String = energyTodayISO()
    /// B-73: the Health burn window (nil fields = calibrating).
    var window: EnergyBurnWindow? = nil
    /// The band service's Health-side reason word, used only when no burn is known at all.
    var reason: String? = nil
    private let theme = JITheme.native
    private var healthBurn: Int? { window?.burnKcal }
    private var value: (kcal: Int?, caption: String) { energyBurnCardValue(window: window, reason: reason) }
    private var average: Double? { value.kcal.map(Double.init) }

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
                        HStack(alignment: .firstTextBaseline, spacing: 6) { burnValue; burnReason.fixedSize() }
                        VStack(alignment: .leading, spacing: 4) { burnValue; burnReason.fixedSize(horizontal: false, vertical: true) }
                    }
                    if healthBurn != nil {
                        let split = EnergyBandCopy.burn(window)
                        Text(verbatim: "Resting \(split.resting) · Active \(split.active) kcal")
                            .jiFont(.subheadline).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("energy.whatYouBurn.split")
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
    private var burnValue: some View {
        Text(verbatim: jiValueText(average, decimals: 0)).jiNumeral(.numeralMedium, tint: average == nil ? .muted : .text)
    }
    /// "kcal a day" with a value; the one true reason word without ("No data").
    private var burnReason: some View {
        Text(value.caption).jiFont(.subheadline, weight: .semibold)
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

/// B-73: "Plan 1800 kcal" (the user's own target), or "Set your goal".
public nonisolated func energyGoalHeaderText(_ goal: Double?) -> String {
    EnergyBandCopy.planHeader(targetKcal: goal)
}

/// B-73 disclaimers under "How we calculate" (verbatim, also on GoalsSetup): align the food
/// tracker's goal, and — until 7 complete Health days — the band-settle note.
struct EnergyBandDisclaimers: View {
    let burn: EnergyBurnWindow?
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MacroGoals.trackerDisclaimer).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("energy-disclaimer")
            if let note = EnergyBandCopy.settleNote(burn) {
                Text(note).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy-settle-note")
            }
        }
    }
}

/// The last 7 complete days' measured burn (`tdeeRaw`, the device's resting + active total),
/// averaged; nil when none. The hub's empirical `tdeeCorrected` is a model estimate, not what
/// the card's copy describes, so it never stands in (rule 5: "— No data", never a guess).
public nonisolated func energyBurnAverage(days: [EnergyDay], today: String) -> Double? {
    let burns = energyLogDays(days: days, today: today).prefix(7)
        .compactMap { d -> Double? in d.tdeeRaw.flatMap { $0.isFinite ? $0 : nil } }
    return burns.isEmpty ? nil : burns.reduce(0, +) / Double(burns.count)
}

/// fixer2 BUG-38/RF2-BURN: the burn card's value + caption — the Health burn with "kcal a day",
/// or no number and the band service's reason ("Not in Health yet" when Health is empty).
public nonisolated func energyBurnCardValue(window: EnergyBurnWindow?, reason: String?) -> (kcal: Int?, caption: String) {
    if let kcal = window?.burnKcal { return (kcal, "kcal a day") }
    return (nil, reason ?? JIMissingReason.noData.rawValue)
}

/// "2300 kcal", or "— No data".
public nonisolated func energyBurnText(days: [EnergyDay], today: String) -> String {
    jiValueOrReasonText(energyBurnAverage(days: days, today: today), decimals: 0, unit: "kcal")
}
