import Foundation
import Testing
import JICore
import JIPersistence
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
