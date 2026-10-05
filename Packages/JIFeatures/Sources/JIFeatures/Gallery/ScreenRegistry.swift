// W-DEAD-2 D2-9: gallery/preview support — compiled into Debug only, never the installed app.
#if DEBUG
import SwiftUI
import JIDesign

/// §8.5 one line per screen that ships in the native language. The sweep test renders every
/// entry in every `SweepMatrix` cell; HT `tests/test_theme_status_ledger.py` checks each name
/// is in `docs/THEME_STATUS.md`. Adding a screen = one entry here + one ledger row.
public nonisolated struct ScreenEntry: Sendable, Identifiable {
    public let name: String
    public let theme: JITheme
    public let make: @MainActor @Sendable () -> AnyView
    public var id: String { name }
    public var slug: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }
    public init(name: String, theme: JITheme = .native, make: @escaping @MainActor @Sendable () -> AnyView) {
        self.name = name; self.theme = theme; self.make = make
    }
}

/// `nonisolated`: the list is read from nonisolated tests; `make` itself is MainActor.
public nonisolated enum ScreenRegistry {
    public static let entries: [ScreenEntry] = [
        ScreenEntry(name: "Native gallery") { AnyView(NativeGalleryView()) },

        // MARK: L4 — chrome + hero screens (append-only; never reorder another lane's block)
        ScreenEntry(name: "Today") { L4Screens.today() },
        ScreenEntry(name: "Recovery") { L4Screens.recovery() },
        ScreenEntry(name: "Readiness rationale") { L4Screens.readinessRationale() },
        ScreenEntry(name: "Gate config") { L4Screens.gateConfig() },
        ScreenEntry(name: "Edit today") { L4Screens.editToday() },

        // MARK: W-B57a L2 — B-57 Today morning flow (Decide → Coach → Day)
        ScreenEntry(name: "Today decide") { L4Screens.todayDecide() },
        ScreenEntry(name: "Today coach") { L4Screens.todayCoach() },
        ScreenEntry(name: "Today day") { L4Screens.todayDay() },
        // W-B57b L2 — Decide's Adjust sheet (verdict override: choice + reason)
        ScreenEntry(name: "Today adjust") { L4Screens.todayAdjust() },
        // W-B65 LC — Decide on an Apple Watch night (hrv band, 7 h sleep, daytime-HRV context arc)
        ScreenEntry(name: "Today decide Apple") { L4Screens.todayDecideApple() },
        // W-DECIDE-HYBRID H-4 — Decide after the call (Strain: today vs the call's max)
        ScreenEntry(name: "Today decide after call") { L4Screens.todayDecideAfterCall() },

        // MARK: W-B46 L2 — B-42 Today components
        ScreenEntry(name: "Trends") { AnyView(TrendsNativePreview()) },   // B-57 W1: full screen (was "Trends card")

        // MARK: L5 — Training · Nutrition · Energy · KPI · Watch · Widgets (append-only)
        ScreenEntry(name: "Training") { AnyView(TrainingNativePreview()) },
        ScreenEntry(name: "Session coach") { AnyView(SessionCoachNativePreview()) },
        ScreenEntry(name: "Weekly plan") { AnyView(WeeklyPlanNativePreview()) },
        ScreenEntry(name: "Send to Watch") { AnyView(SendToWatchNativePreview()) },
        ScreenEntry(name: "Nutrition") { AnyView(NutritionNativePreview()) },
        ScreenEntry(name: "Meal detail") { AnyView(MealDetailNativePreview()) },   // B-57 W1: read-only (was "Nutrition log")
        ScreenEntry(name: "Weigh-in") { AnyView(WeighInNativePreview()) },
        ScreenEntry(name: "Energy") { AnyView(EnergyNativePreview()) },
        ScreenEntry(name: "KPIs") { AnyView(KpiListNativePreview()) },
        ScreenEntry(name: "KPI detail") { AnyView(KpiDetailNativePreview()) },
        // W-GUI R2: the RHR (20) and Sleep (21) fixtures of the same screen.
        ScreenEntry(name: "KPI detail RHR") { AnyView(KpiDetailNativePreview(metric: .rhr)) },
        ScreenEntry(name: "KPI detail sleep") { AnyView(KpiDetailNativePreview(metric: .sleep)) },
        ScreenEntry(name: "KPI detail nutrition") { AnyView(KpiDetailNutritionNativePreview()) },

        // MARK: L6 — Journal · Mind · Coach · Settings & Data (B-33 Phase B). Append-only.
        ScreenEntry(name: "Journal") { L6Fixtures.journal() },
        ScreenEntry(name: "Journal calendar") { L6Fixtures.journalCalendar() },
        ScreenEntry(name: "Journal entry") { L6Fixtures.journalEntry() },
        ScreenEntry(name: "Mind") { L6Fixtures.mind() },
        ScreenEntry(name: "Mind check-in") { L6Fixtures.mindCheckIn() },
        ScreenEntry(name: "Mind event") { L6Fixtures.mindEvent() },
        ScreenEntry(name: "WHO-5") { L6Fixtures.who5() },
        ScreenEntry(name: "Goals") { L6Fixtures.goals() },
        ScreenEntry(name: "Goals setup") { L6Fixtures.goalsSetup() },
        ScreenEntry(name: "Settings") { L6Fixtures.settings() },

        // MARK: W-B41 L1 — B-41 Settings group sub-screens (the DEBUG `developer` group is
        // excluded on purpose: it is not compiled into a Release build).
        ScreenEntry(name: "Settings sync") { L6Fixtures.settingsSync() },
        ScreenEntry(name: "Settings widgets") { L6Fixtures.settingsWidgets() },
        ScreenEntry(name: "Settings home") { L6Fixtures.settingsHome() },
        ScreenEntry(name: "Settings KPIs") { L6Fixtures.settingsKpis() },
        ScreenEntry(name: "Settings haptics") { L6Fixtures.settingsHaptics() },
        ScreenEntry(name: "Settings health") { L6Fixtures.settingsHealth() },
        ScreenEntry(name: "Settings about") { L6Fixtures.settingsAbout() },
        ScreenEntry(name: "Hub connection") { L6Fixtures.hubConnection() },
        ScreenEntry(name: "Appearance") { L6Fixtures.appearance() },
        ScreenEntry(name: "Backup") { L6Fixtures.backup() },
        ScreenEntry(name: "Export") { L6Fixtures.export() },
        ScreenEntry(name: "Version") { L6Fixtures.version() },
        ScreenEntry(name: "Version crash") { L6Fixtures.versionWithCrash() },
        ScreenEntry(name: "Local mirrors") { L6Fixtures.localMirrors() },
        ScreenEntry(name: "Data quality") { L6Fixtures.dataQuality() },
        ScreenEntry(name: "Reminders") { L6Fixtures.reminders() },
        ScreenEntry(name: "Health permission") { L6Fixtures.healthPermission() },
        // MARK: W-B57-W4 LC — onboarding (boards 3 Plan & train/08–11)
        ScreenEntry(name: "Onboarding welcome") { AnyView(OnboardingNativePreview(step: .welcome)) },
        ScreenEntry(name: "Onboarding baseline") { AnyView(OnboardingNativePreview(step: .baseline)) },
        ScreenEntry(name: "Onboarding safety") { AnyView(OnboardingNativePreview(step: .safety)) },
        ScreenEntry(name: "Onboarding gate") { AnyView(OnboardingNativePreview(step: .gate)) },
        // MARK: B-57 W5 — Week & glance
        ScreenEntry(name: "Training week") { L6Fixtures.trainingWeek() },
        // MARK: W-GUI-2 X2 — state faces (mockups 57–60), names from `ScreenStateFaces.registryNames`
        ScreenEntry(name: "Today offline") { ScreenStateFaces.offline() },
        ScreenEntry(name: "Today first week") { ScreenStateFaces.firstWeek() },
        ScreenEntry(name: "Today error") { ScreenStateFaces.error() },
        ScreenEntry(name: "Today no source") { ScreenStateFaces.noSource() },
        // MARK: W-TGT L3 — Settings › Targets (mock 01) + the one editor sheet (mock 02)
        ScreenEntry(name: "Targets") { TargetsFixtures.targets() },
        ScreenEntry(name: "Target editor") { TargetsFixtures.editor() },
        // W-TGT fixer: the HR cap in the same editor (Limit), Sync & hub, Home & widgets (mock 05)
        ScreenEntry(name: "Target editor cap") { TargetsFixtures.editorCap() },
        ScreenEntry(name: "Sync & hub") { L6Fixtures.settingsSyncHub() },
        ScreenEntry(name: "Home & widgets") { L6Fixtures.homeWidgets() },
    ]
}
#endif
