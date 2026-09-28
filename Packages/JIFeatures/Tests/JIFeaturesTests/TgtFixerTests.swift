import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-TGT fixer (verifier rows 1c · 1e · 1f): the editor sheet, Settings (mock 04) and
// Home & widgets (mock 05). Test values only.

// MARK: - 1c editor

@Test func aFieldShowsTheSameGroupedNumberAsItsCaption() {
    #expect(targetsFieldText(1600, decimals: 0) == "1,600")
    #expect(targetsFieldText(2117, decimals: 0) == "2,117")
    #expect(targetsFieldText(0.8, decimals: 2) == "0.80")
    #expect(targetsFieldText(150, decimals: 0) == "150")
    let d = TargetEditDraft(subject: .goal(.kcal), document: .empty)
    #expect(d.ruleTexts[.weekKcalFloor] == "1,600")
    #expect(targetsRuleValueText(.weekKcalFloor, 1600) == "1,600 kcal")
    #expect(TargetEditDraft.stepped("1,600", by: 50, decimals: 0, from: nil) == "1,650")
    #expect(TargetEditDraft.stepped("", by: 500, decimals: 0, from: 9800) == "10,300")
}

@Test func theHrCapIsEditedInTheSameSheetAsALimit() throws {
    var cap = TargetsDocument()
    cap.limits = TargetLimits(hrCapBpm: 168, hrCapConfirmedOn: "2026-09-20", zones: nil, avoidZone5: false)
    var d = TargetEditDraft(subject: .hrCap, document: cap)
    #expect(d.limitText == "168")
    #expect(TargetSubject.hrCap.isLimit && !TargetSubject.goal(.kcal).isLimit)
    d.limitText = "172"
    #expect(try d.applied(to: cap).get().limits.hrCapBpm == 172)
    #expect(d.capText == "172")
    d.limitText = ""
    #expect(try d.applied(to: cap).get().limits.hrCapBpm == nil)   // no cap = none
    #expect(d.capText == nil)
    d.limitText = "fast"
    #expect(d.applied(to: cap) == .failure(.unreadable("HR cap")))
    #expect(TargetEditDraft(subject: .hrCap, document: .empty).limitText.isEmpty)   // never seeded
}

@Test func theNormalBlockIsComputedTheSameWayFromEveryEntryPoint() {
    // 28 days of 1,600 ± a little → a band; the same pure call KPI detail uses.
    var points: [(date: String, value: Double?)] = []
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    let today = f.date(from: "2026-09-28")!
    for i in 1...40 {
        let day = f.string(from: today.addingTimeInterval(Double(-i) * 86_400))
        points.append((day, 1600 + Double(i % 5) * 20))
    }
    let info = targetNormalInfo(points: points, today: "2026-09-28", decimals: 0, unit: "kcal")
    #expect(info?.normalText != nil)
    #expect(info?.lastSevenText?.hasSuffix(" kcal") == true)
    #expect(targetNormalInfo(points: [], today: "2026-09-28", decimals: 0, unit: "kcal") == nil)
    #expect(targetsNormalMetric(.goal(.kcal)) == .kcal)
    #expect(targetsNormalMetric(.hrCap) == nil)
}

@Test func theNoNormalTextNeverClaimsTooFewDays() {
    #expect(!targetEditorNoNormalText.contains("enough days"))
}

// MARK: - 1e Settings (mock 04): Connection · Today · Phone · App

@Test func settingsRootIsMock04() {
    #expect(SettingsRoot.headers == ["Connection", "Today", "Phone", "App"])
    func ids(_ g: SettingsRootGroup) -> [String] { SettingsRoot.rows.filter { $0.group == g }.map(\.id) }
    #expect(ids(.connection) == ["hub", "health"])
    #expect(ids(.today) == ["home", "targets"])
    #expect(ids(.phone) == ["appearance", "haptics", "reminders"])
    #expect(ids(.app).first == "about")
    #if DEBUG
    #expect(ids(.app) == ["about", "developer"])
    #else
    #expect(ids(.app) == ["about"])
    #endif
    let hub = SettingsRoot.rows.first { $0.id == "hub" }
    #expect(hub?.kind == .push(title: "Sync & hub", systemImage: "arrow.triangle.2.circlepath", placeholder: nil))
    #expect(hub?.sectionIds.first == SyncNowSection.sectionId)          // Sync now leads the Sync & hub screen
    #expect(settingsDataSectionIds.allSatisfy { hub?.sectionIds.contains($0) == true })
    #expect(SettingsRoot.rows.first { $0.id == "haptics" }?.kind
            == .push(title: "Haptics & notifications", systemImage: "iphone.radiowaves.left.and.right", placeholder: nil))
    #expect(SettingsRoot.rows.first { $0.id == "home" }?.kind == .homeWidgets)
}

@Test func settingsRootSubtitlesSayWhatIsBehindEachRow() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-09-28T13:20:00Z")!
    let synced = ISO8601DateFormatter().date(from: "2026-09-28T12:40:00Z")!
    #expect(settingsSyncHubSubtitle(lastSync: synced, now: now, calendar: cal) == "Hub synced 12:40 · backup, data quality, mirrors, export")
    #expect(settingsSyncHubSubtitle(lastSync: nil, now: now, calendar: cal) == "Not synced yet · backup, data quality, mirrors, export")
    #expect(homeWidgetsSubtitle(squares: 6) == "Card order · 6 squares on Today · widgets · Live Activity")
    #expect(settingsTodayFooter.contains("Targets"))
}

// MARK: - 1f Home & widgets (mock 05)

@Test func homeWidgetsListsTodaysCardsInTodaysOrder() {
    let cards = homeWidgetsCards(squares: 6)
    #expect(cards.map(\.title) == ["Decide / Coach / Day", "Next session", "Fuel today", "Tonight", "KPI squares", "Trends · Week review"])
    #expect(cards.first?.state == "always first")
    #expect(cards.first { $0.title == "KPI squares" }?.state == "6 chosen")
    #expect(homeWidgetsRows.map(\.title) == ["Lock-screen widget", "Workout Live Activity"])
}

@Test func kpiSquaresReadEveryGoalFromTargets() {
    var d = TargetsDocument()
    d.goals.kcal = KcalGoal(goalKcal: 2117, basis: .subtractDeficit(.deficit(kcalPerDay: 500)))
    d.goals.proteinG = 155
    #expect(kpiListGoalCaption(.kcal, value: 1850, targets: d) == "goal 1,617")
    #expect(kpiListGoalCaption(.protein, value: 148, targets: d) == "goal 155 g")
    #expect(kpiListGoalCaption(.carbs, value: 214, targets: d) == "no goal")
    #expect(kpiListGoalCaption(.kcal, value: 1850, targets: nil) == nil)   // no document: the nutrition snapshot decides
    #expect(kpiListGoalCaption(.hrv, value: 28, targets: d) == nil)
}

@Test @MainActor func kpiSquaresReadTheCachedHealthDayWhenTheFeedIsEmpty() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put(EnergyBandService.cacheKey, [HealthDailyTotals(date: "2026-09-28", dietaryKcal: 1850)])
    let vm = KpiListViewModel(healthProvider: KpiFakeProvider(failing: true), nutritionProvider: KpiFakeProvider(failing: true),
                              targetsProvider: KpiFakeProvider(failing: true), prefStore: PrefStore(db: try .inMemory()),
                              cache: cache, healthFeed: HealthDailyTotalsFeed())
    await vm.load()
    #expect(vm.healthTotals.map(\.dietaryKcal) == [1850])
}

@Test func thePickerIsCalledOnToday() {
    #expect(kpiListTitle == "On Today")
}
