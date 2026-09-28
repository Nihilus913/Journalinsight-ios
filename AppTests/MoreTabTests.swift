import Testing
import Foundation
import JICore
import JIFeatures
import JIPersistence
@testable import JournalInsight

struct MoreTabTests {
    @Test func moreIsTrackPracticeAppWithNoChallenges() {
        let s = RootTabView.moreSections
        #expect(s.map(\.header) == ["Track", "Practice", "App"])
        #expect(s.flatMap(\.rows) == ["Nutrition", "Energy", "My KPIs", "Goals", "Mind", "Settings"])
        #expect(!s.flatMap(\.rows).contains("Challenges"))
    }

    @Test func myKpisRowShowsTheChosenCount() {
        #expect(RootTabView.moreKpiText(count: 5) == "5 chosen")
    }

    // W-FIX2 BUG-47 (board 4/04): the Settings row reads "Hub synced 07:41", not a pill.
    @Test func settingsRowReadsHubSyncedTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let d = Date(timeIntervalSince1970: 1_790_314_860)   // 2026-09-25 05:41Z = 07:41 Zurich
        #expect(RootTabView.moreSettingsText(syncedAt: d, calendar: cal) == "Hub synced 07:41")
        #expect(RootTabView.moreSettingsText(syncedAt: nil) == "Not synced yet")
    }

    // W-FIX4 PF-04: More's time = Today's sync rule (newer of hub sync / HealthKit upload), never
    // the moment Today fetched.
    @Test @MainActor func settingsRowUsesTheSyncTimeNotTheFetchTime() async throws {
        let model = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), uploadRecord: nil)
        await model.load()
        #expect(model.fetchedAt != nil)
        #expect(RootTabView.moreSettingsDate(model) == model.syncedAt)
        #expect(RootTabView.moreSettingsDate(nil) == nil)
    }

    // W-FIX4 fixer PF-04: every tab stack is handed the shell's one sync instant (Today's rule),
    // so Recovery/Training/Energy/Nutrition name the same time as Day, the gate and More.
    @Test @MainActor func tabStacksAreHandedTheShellSyncTime() async throws {
        let model = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), uploadRecord: nil)
        await model.load()
        #expect(model.syncedAt != nil)
        #expect(RootTabView.tabSyncedAt(model) == model.syncedAt)
        #expect(RootTabView.tabSyncedAt(nil) == nil)
    }

    // W-FIX4 fixer PF-04: the wiring itself — `tabStack` injects `jiSyncedAt`, and the shell primes
    // Today's model on launch so a first tab other than Day still knows the hub's last sync.
    @Test func tabStackInjectsTheSyncTimeAndTheShellPrimesIt() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
        let stack = try #require(src.range(of: "private func tabStack<"))
        let tail = String(src[stack.lowerBound...].prefix(1_600))
        // W-B57-W3 fixer: via the shared `shellStackEnvironment` (checked in kpiSheetStackGetsTheShellEnvironment).
        #expect(tail.contains("shellStackEnvironment("))
        #expect(src.contains(".task(id: providerRevision) { await primeShellSync() }"))
    }

    // W-B57-W3 fixer PF-04: the My KPIs sheet's own stack gets the same shell environment as every
    // tab stack (sync instant + recovery insight) — a sheet does not inherit a tab stack's
    // environment, so KpiDetail opened from My KPIs said "Not synced yet" while the tab path said 09:00.
    @Test func kpiSheetStackGetsTheShellEnvironment() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
        let helper = try #require(src.range(of: "func shellStackEnvironment<"))
        let body = String(src[helper.lowerBound...].prefix(600))
        #expect(body.contains(".environment(\\.jiSyncedAt, Self.tabSyncedAt(todayModel))"))
        #expect(body.contains(".environment(\\.recoveryInsight, recoveryInsight)"))
        let sheet = try #require(src.range(of: ".sheet(isPresented: $showKpiList"))
        let sheetBody = String(src[sheet.lowerBound...].prefix(2_000))
        let end = try #require(sheetBody.range(of: ".sheet(isPresented: $showSettings"))
        #expect(sheetBody[..<end.lowerBound].contains("shellStackEnvironment("))
        let stack = try #require(src.range(of: "private func tabStack<"))
        #expect(String(src[stack.lowerBound...].prefix(1_800)).contains("shellStackEnvironment("))
    }

    // W-FIX4 fixer PF-04: prime only when nothing live is known and no load is already running.
    @Test @MainActor func shellSyncPrimesOnlyAnIdleModel() async throws {
        let model = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), uploadRecord: nil)
        #expect(RootTabView.shouldPrimeShellSync(model))
        await model.load()
        #expect(!RootTabView.shouldPrimeShellSync(model))
        #expect(!RootTabView.shouldPrimeShellSync(nil))
    }

    // W-FIX4 BUG-30: the forced gate carries no "Today" page title (Decide's date line is the heading).
    @Test func forcedGateHasNoPageTitle() {
        #expect(RootTabView.gateNavigationTitle(pageName: "Today") == "")
        #expect(RootTabView.gateShowsDateSubtitle == false)
    }

    // W-FIX2 BUG-42: More's Goals row = the goal's start → target, as Settings shows (80.2 → 75.0).
    @Test func goalsRowIsStartToTargetLikeSettings() {
        let goals = Goals(weight: WeightGoal(baseKg: 80.2, targetKg: 75.0, targetDate: "2026-10-31"), strength: [], nutrition: NutritionGoal())
        #expect(RootTabView.moreGoalsRowValue(goals).text == "80.2 → 75.0 kg")
        #expect(settingsGoalsTrailing(goals) == "80.2 → 75.0 kg")
        #expect(RootTabView.moreGoalsRowValue(nil).lead == "—")
    }

    // W-B57-W2 fixer MORE-NUTRITION-GOAL: the More Nutrition row divides by the user's target only;
    // YAZIO's day goal (1739/1617) is never passed in, and an unset goal shows consumed alone.
    @Test func nutritionRowUsesOnlyTheUserKcalTarget() {
        #expect(RootTabView.moreNutritionRowValue(consumedKcal: 1200, userGoals: nil).text == "1,200 kcal")
        #expect(RootTabView.moreNutritionRowValue(consumedKcal: 1200, userGoals: .unset).text == "1,200 kcal")
        let mine = MacroGoals(kcal: KcalGoal(goalKcal: 1900, basis: .includesDeficit))
        #expect(RootTabView.moreNutritionRowValue(consumedKcal: 1200, userGoals: mine).text == "1,200 / 1,900 kcal")
        #expect(RootTabView.moreNutritionRowValue(consumedKcal: nil, userGoals: mine).lead == "—")
    }

    // W-B57-W5 guard BUG-47 (board 4/04): the App card's Settings entry is ONE `JIChevronRow`
    // whose trailing value is the "Hub synced 07:41" text — no pill, no second Settings row.
    @Test func appCardSettingsIsOneChevronRow() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
        let head = try #require(src.range(of: "JISectionHeader(\"App\")"))
        let rest = src[head.lowerBound...]
        let end = try #require(rest.range(of: "\"more.caption\""))
        let card = String(rest[..<end.lowerBound])
        #expect(card.components(separatedBy: "\"more.settings\"").count == 2)          // exactly one Settings row
        #expect(card.components(separatedBy: "moreSettingsText(").count == 2)
        #expect(!card.contains("SyncedPill"))                                          // text, never a pill
        let id = try #require(card.range(of: "\"more.settings\""))
        let button = try #require(card[..<id.lowerBound].range(of: "Button { showSettings = true } label: {", options: .backwards))
        let row = String(card[button.upperBound..<id.lowerBound])
        #expect(row.components(separatedBy: "JIChevronRow {").count == 2)
        #expect(row.contains("MoreRowLabel(\"Settings\""))
        #expect(row.contains("moreSettingsText(syncedAt: Self.moreSettingsDate(todayModel))"))
    }
}
