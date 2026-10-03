import Foundation
import Testing
import JICore
import JIPersistence
import JIDesign
@testable import JIFeatures

// W-FIX11 lane A — sim bug hunt 2026-10-01 (HealthTraining docs/audits/2026-10-01-bug-hunt).

private let fix11Modified = verdictParts("MODIFIED — Cap the long run at ~45min easy, or walk it.")

@MainActor
private func fix11VM(_ provider: VerdictOverrideFakeProvider = VerdictOverrideFakeProvider(),
                     current: VerdictOverride? = nil) throws -> VerdictOverrideViewModel {
    VerdictOverrideViewModel(provider: provider, outbox: Outbox(db: try AppDatabase.inMemory()), current: current,
                             now: { Date(timeIntervalSince1970: 1_790_000_000) })
}

// MARK: - H1-01 (S1): Go after Adjust keeps the user's call

@Test func h1_01_goKeepsTheShownRestOverride() {
    let rest = VerdictOverride(date: "2026-10-01", choice: .rest, reason: "Schedule constraint",
                               session: "Rest — walks only", createdAt: "2026-10-01T11:33:59+02:00")
    #expect(decideGoChoice(override: rest) == nil)   // nil = keep, no write
    #expect(decideGoChoice(override: nil) == .accept)
    let accepted = VerdictOverride(date: "2026-10-01", choice: .accept, reason: nil, session: "Long Zone 2", createdAt: nil)
    #expect(decideGoChoice(override: accepted) == nil)
}

@Test @MainActor func h1_01_goOverAnOverrideNeverPostsAccept() async throws {
    let provider = VerdictOverrideFakeProvider()
    let rest = VerdictOverride(date: "2026-10-01", choice: .rest, reason: "Schedule constraint",
                               session: "Rest — walks only", createdAt: "2026-10-01T11:33:59+02:00")
    let vm = try fix11VM(provider, current: rest)
    let settled = await decideGo(model: vm, date: "2026-10-01", override: rest, parts: fix11Modified, sessionForToday: nil)
    #expect(settled == false)          // nothing written: the caller just advances
    #expect(provider.setCalls.isEmpty)
    #expect(vm.current == rest)
}

@Test @MainActor func h1_01_goWithoutAnOverrideAccepts() async throws {
    let provider = VerdictOverrideFakeProvider()
    let vm = try fix11VM(provider)
    let settled = await decideGo(model: vm, date: "2026-10-01", override: nil, parts: fix11Modified, sessionForToday: nil)
    #expect(settled == true)
    #expect(provider.setCalls.map(\.1) == [.accept])
}

// MARK: - H1-02 (S2): Today keeps the just-saved call over an older /morning

@Test @MainActor func h1_02_anOlderMorningNeverWipesThisDevicesCall() async throws {
    let vm = try fix11VM()
    await vm.setOverride(date: "2026-10-01", choice: .rest, reason: "Schedule constraint")
    #expect(vm.current?.choice == .rest)
    vm.seedFromHub(nil)                   // the /morning fetched before the save
    #expect(vm.current?.choice == .rest)
    let older = VerdictOverride(date: "2026-10-01", choice: .accept, reason: nil, session: "x", createdAt: "2026-09-23T05:00:00+02:00")
    vm.seedFromHub(older)
    #expect(vm.current?.choice == .rest)
    let newer = VerdictOverride(date: "2026-10-01", choice: .full, reason: nil, session: "y", createdAt: "2026-09-23T07:00:00+02:00")
    vm.seedFromHub(newer)                 // another device's later call wins
    #expect(vm.current?.choice == .full)
}

@Test @MainActor func h1_02_beforeAnyWriteTheHubSeeds() throws {
    let vm = try fix11VM()
    let hub = VerdictOverride(date: "2026-10-01", choice: .rest, reason: nil, session: "Rest", createdAt: "2026-10-01T09:00:00+02:00")
    vm.seedFromHub(hub)
    #expect(vm.current == hub)
    vm.seedFromHub(nil)
    #expect(vm.current == nil)
}

// MARK: - H1-03 / H1-04 (S2): the coach card says the user's call and dates old vitals

private func fix11Morning(_ verdict: String) -> MorningResponse {
    try! JSON.decoder.decode(MorningResponse.self, from: Data("""
    {"today_activities": [], "verdict": "\(verdict)", "verdict_date": "2026-10-01",
     "experiment": null, "carbs_3d_avg": 150, "carb_watch_floor": 120, "hrv_series": []}
    """.utf8))
}

@Test func h1_03_coachChangeReadsTheUsersRest() {
    let rest = VerdictOverride(date: "2026-10-01", choice: .rest, reason: "Schedule constraint", session: "Rest — walks only", createdAt: nil)
    let c = CoachContentBuilder.build(morning: fix11Morning("GO (auto-regulated) — Long Zone 2 75-90min"), gate: nil, recovery: [],
                                      override: rest)
    #expect(c.change == CoachContentBuilder.restChange)
    #expect(!c.change.contains("Modified"))
}

@Test func h1_03_coachChangeReadsTheUsersFullAndModified() {
    let m = fix11Morning("GO (auto-regulated) — Long Zone 2 75-90min")
    let full = VerdictOverride(date: "2026-10-01", choice: .full, reason: nil, session: "Long Zone 2 75-90min", createdAt: nil)
    #expect(CoachContentBuilder.build(morning: m, gate: nil, recovery: [], override: full).change == "Your call: Long Zone 2 75-90min.")
    let accept = VerdictOverride(date: "2026-10-01", choice: .accept, reason: nil, session: "Long Zone 2 75-90min", createdAt: nil)
    #expect(CoachContentBuilder.build(morning: m, gate: nil, recovery: [], override: accept).change.hasPrefix("Modified: "))
}

@Test func h1_04_coachSignalsFromAnEarlierNightSayTheirDayAndTheHubReason() {
    let rec = (0..<4).map { i in RecoveryDay(date: "2026-09-\(27 + i)", sleepScore: [87, 87, 87, 80][i], rhrBpm: [73, 73, 73, 62][i],
                                             hrvRmssdMs: [22, 22, 22, 23][i]) }
    let c = CoachContentBuilder.build(morning: fix11Morning("GO (auto-regulated) — Long Zone 2 75-90min"), gate: nil, recovery: rec,
                                      verdictReason: "Amber (overnight vitals not synced yet): cap the long run at ~45min easy, or walk it.",
                                      today: "2026-10-01", locale: Locale(identifier: "en_GB"))
    #expect(c.signals.first == "Sleep 80 vs 87 avg (30 Sep)")
    #expect(c.signals.allSatisfy { $0.hasSuffix("(30 Sep)") })
    #expect(c.why == "overnight vitals not synced yet")
    #expect(coachOverlayNote(c)?.hasPrefix("Why: overnight vitals not synced yet · Sleep 80") == true)
}

@Test func h1_04_todaysSignalsStayUndated() {
    let rec = (0..<4).map { i in RecoveryDay(date: "2026-09-\(27 + i)", sleepScore: [87, 87, 87, 80][i]) }
    let c = CoachContentBuilder.build(morning: nil, gate: nil, recovery: rec, today: "2026-09-30", locale: Locale(identifier: "en_GB"))
    #expect(c.signals == ["Sleep 80 vs 87 avg"])
    #expect(c.why == nil)
}

// MARK: - H1-05 (S2): Training follows the user's call

@Test func h1_05_trainingSubtitleSaysTheUsersRest() {
    let rest = VerdictOverride(date: "2026-10-01", choice: .rest, reason: nil, session: "Rest — walks only", createdAt: nil)
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let s = trainingSubtitle(verdict: "GO (auto-regulated) — Long Zone 2 75-90min", isStale: false, date: date,
                             override: rest, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
    #expect(s.word == "Rest")
    #expect(s.tone == .muted)
    let none = trainingSubtitle(verdict: "GO (auto-regulated) — Long Zone 2 75-90min", isStale: false, date: date,
                                locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
    #expect(none.word == "Modified")
}

@Test func h1_05_readinessCardAndHeroFollowTheCall() {
    let rest = VerdictOverride(date: "2026-10-01", choice: .rest, reason: nil, session: "Rest — walks only", createdAt: nil)
    let shown = gateDetailShownParts(verdict: "GO (auto-regulated) — Long Zone 2 75-90min", override: rest)
    #expect(verdictUserWord(shown) == "Rest")
    #expect(trainingHeroOffersStart(override: rest) == false)
    #expect(trainingHeroOffersStart(override: nil) == true)
}

// MARK: - H1-06 (S2): VoiceOver reads Decide's verdict word

@Test func h1_06_decideVerdictWordLabelIsTheWord() {
    let shown = effectiveVerdictParts(parts: verdictParts("GO (auto-regulated) — Long Zone 2 75-90min"), override: nil)
    #expect(decideVerdictWordAccessibilityLabel(shown, syncing: false) == "Modified")
    #expect(decideVerdictWordAccessibilityLabel(shown, syncing: true) == "Syncing")
    #expect(!decideVerdictWordAccessibilityLabel(shown, syncing: false).hasPrefix("Readiness"))
}

// MARK: - H1-07 (S2): a Modified day held for missing vitals says so first

private func fix11Missing(_ key: String) -> GateSignal {
    GateSignal(key: key, label: key, value: nil, unit: key == "sleep_h" ? "h" : "ms", threshold: 7,
               direction: .min, status: .missing)
}

@Test func h1_07_allMissingSaysTheRealReasonInOneSentence() {
    let signals = ["sleep_score", "hrv", "rhr", "sleep_h", "recovery"].map(fix11Missing)
    let s = gateRationaleWhySentence(signals: signals, why: "overnight vitals not synced yet")
    #expect(s == "Overnight vitals not synced yet, so no overnight signal has a reading and today is held back.")
    #expect(s?.contains("left out") == false)
    let rows = gateRationaleCountedRows(signals: signals, normals: [:], load: nil, missingIsTheReason: true)
    #expect(rows.filter { $0.id != "load" }.allSatisfy { $0.sentence == "No overnight value yet — this is why today is held back." })
    // without a hub reason the old wording stays
    #expect(gateRationaleWhySentence(signals: signals)?.contains("left out") == true)
}

// MARK: - H1-15 (+H2-05) (S2): one sync time, offline never green

@Test @MainActor func h1_15_theHubsLastSyncSurvivesAnOfflineRelaunch() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let now = ISO8601DateFormatter().date(from: "2026-09-25T10:51:00Z")!
    let online = TodayViewModel(provider: Fix2HubStub(days: TodayDataFix2Tests.hubDays, summary: nil), cache: cache, now: { now })
    await online.load()
    let synced = try #require(online.syncedAt)
    // Relaunch with the hub down: the same cache, a provider whose sync status fails.
    let offline = TodayViewModel(provider: Fix2NoSummaryStub(days: []), cache: cache, now: { now })
    await offline.load()
    #expect(offline.syncedAt == synced)   // never "Not synced yet"
}

@Test func h1_15_offlinePillNamesTheOneSyncTime() {
    let sync = Date(timeIntervalSince1970: 1_790_000_000)
    let fetch = sync.addingTimeInterval(9_000)
    #expect(offlinePillLastDate(syncedAt: sync, fetchedAt: fetch) == sync)
    #expect(offlinePillLastDate(syncedAt: nil, fetchedAt: fetch) == fetch)
}

// MARK: - H1-10 (S3): the square's sparkline ends on its own day

@Test func h1_10_squareSparklineEndsOnTheAsOfDay() {
    let old = TodayChip(id: "hrv", label: "HRV", value: 23, unit: "ms", points: [20, 22, 23], sourceMissing: false, asOf: "as of 30 Sep")
    #expect(todaySummaryCardSpec(for: old).sparklineEndLabel == "30 Sep")
    let fresh = TodayChip(id: "hrv", label: "HRV", value: 23, unit: "ms", points: [20, 22, 23], sourceMissing: false)
    #expect(todaySummaryCardSpec(for: fresh).sparklineEndLabel == nil)
}

// MARK: - H2-20 (S3): More › Apple Health opens the Apple Health screen

@Test func h2_20_appleHealthShortcutIsTheSettingsHealthRow() {
    let row = settingsShortcutRow("health")
    #expect(row?.sectionIds == ["l0.health"])
    if case .push(let title, _, _)? = row?.kind { #expect(title == "Apple Health") } else { Issue.record("not a push row") }
}

// MARK: - H1-08 (S3): "Last 3 days" keeps a MODIFIED day's change line

@Test func h1_08_modifiedDayKeepsItsChangeLine() {
    #expect(gateDayPrescription(verdict: "MODIFIED — swap intervals for easy Z2 30-40min",
                                session: "Norwegian 4x4 intervals", reason: nil) == "Swap intervals for easy Z2 30-40min")
    #expect(gateDayPrescription(verdict: "GO — Full Upper", session: "Full Upper", reason: nil) == nil)
    #expect(gateDayPrescription(verdict: "MODIFIED — Easy Z2", session: "Easy Z2", reason: nil) == nil)
}

// MARK: - H1-09 (S3): the weekly nutrition note never reads as today's reason

@Test func h1_09_readinessCardLabelsTheWeeklyNote() {
    let line = gateDetailWeeklyCaption("Not enough tracked days this week for a nutrition call.")
    #expect(line == "Weekly nutrition (not today's call): not enough tracked days this week for a nutrition call.")
}

// MARK: - H1-14 (S3): the week count is the strip's — placed session days, any done day counts

@Test func h1_14_weekCountFollowsTheStrip() {
    func day(_ wd: Int, _ k: TrainingWeekDayKind, _ done: Bool?) -> TrainingWeekDay {
        TrainingWeekDay(weekday: wd, date: "2026-09-\(28 + wd)", kind: k, sessionName: k == .rest ? nil : "s\(wd)", sessionId: nil, done: done, isToday: wd == 3)
    }
    // 4 strength sessions in the plan, only 3 placed; Mon strength done, Thu long run done today.
    let days = [day(0, .strength, true), day(1, .interval, nil), day(2, .strength, nil), day(3, .longRun, true),
                day(4, .strength, nil), day(5, .rest, nil), day(6, .rest, nil)]
    let w = TrainingWeekSummary(days: days, planTotal: 4, assigned: 3, planDone: 1, next: nil)
    #expect(w.doneText == "2 of 5 done")
    #expect(dayWeekReviewValue(w) == "2 of 5 sessions")
}

// MARK: - H1-12 / H1-13 (S3): Trends never passes an old weigh-in or 2 logged days as "7 days"

private func fix11Daily(_ date: String, _ values: [String: Double?]) -> DailyKpiRow {
    var r = try! JSON.decoder.decode(DailyKpiRow.self, from: Data("{\"date\":\"\(date)\"}".utf8))
    r.values = values
    return r
}

@Test func h1_12_oldWeighInIsLabelledAsTheLastReading() {
    let daily = [fix11Daily("2026-09-19", ["weight_kg": 79.5])] + (24...30).map { fix11Daily("2026-09-\($0)", ["weight_kg": nil]) }
    let w = trendsCards(recovery: [], daily: daily, averages: nil, today: "2026-10-01").first { $0.id == "weight" }!
    #expect(w.value == 79.5)
    #expect(w.asOf?.hasPrefix("Last weigh-in") == true)
    #expect(trendsValueLabel(w) == "last reading")
    #expect(normalBarAccessibilityValue(value: 79.5, normal: nil, median: nil, goal: nil, unit: "kg", decimals: 1,
                                        valueLabel: trendsValueLabel(w)).hasPrefix("last reading 79.5 kg"))
}

@Test func h1_13_nutritionCardSaysHowManyDaysItAverages() {
    let daily = (24...30).map { d in fix11Daily("2026-09-\(d)", ["kcal_consumed": d >= 28 && d <= 29 ? 1431 : nil]) }
    let k = trendsCards(recovery: [], daily: daily, averages: nil, today: "2026-10-01").first { $0.id == "kcal" }!
    #expect(k.asOf == "2 of 7 days logged")
    let full = (24...30).map { d in fix11Daily("2026-09-\(d)", ["kcal_consumed": 1900]) }
    #expect(trendsCards(recovery: [], daily: full, averages: nil, today: "2026-10-01").first { $0.id == "kcal" }!.asOf == nil)
}

// MARK: - H1-18 (S3): the Sleep square's number says what it is

@Test func h1_18_sleepSquareValueHasAUnit() {
    let sleep = TodayChip(id: "sleep", label: "Sleep", value: 80, unit: nil, points: [80, 87], sourceMissing: false)
    #expect(todaySummaryCardSpec(for: sleep).unit == "score")
    let none = TodayChip(id: "sleep", label: "Sleep", value: nil, unit: nil, points: [], sourceMissing: false)
    #expect(todaySummaryCardSpec(for: none).unit == nil)
}
