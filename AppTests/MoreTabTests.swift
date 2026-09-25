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
        #expect(tail.contains(".environment(\\.jiSyncedAt, Self.tabSyncedAt(todayModel))"))
        #expect(src.contains(".task(id: providerRevision) { await primeShellSync() }"))
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
}
