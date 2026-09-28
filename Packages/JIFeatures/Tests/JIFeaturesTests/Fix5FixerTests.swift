import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-FIX5 fixer — the verifier's failures (WD-2, W4-3, X2, W4-2, TR-zones, KPI-sleep-block,
// KPI-legend, Goals-stale).

private func fix5Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

/// WD-2: My KPIs' Load square read "— No data" while Today showed 163 min — the list never passed
/// the live Load reading into the catalogue.
@Test func wd2KpiListPassesTheLoadReading() throws {
    let body = try fix5Source("Sources/JIFeatures/Kpi/KpiListView.swift")
    #expect(body.contains("@Environment(\\.recoveryInsight)"))
    #expect(body.contains("load: recoveryInsight?.loadReading"))
}

/// W4-3: Settings said "Reminders 1 on" with Readiness floor + HR cap check on — the row never
/// read the pending HR-cap re-check.
@Test func w43RemindersRowCountsTheHrCapCheck() throws {
    let body = try fix5Source("Sources/JIFeatures/Settings/Sections/RemindersSection.swift")
    // W-FIX6 F6-16 supersedes the prefs + hrCapCheckOn sum: the row counts the pending requests,
    // and `activeCount()` includes the HR-cap re-check (Fix6L2Tests pins that).
    #expect(body.contains("activeCount()"))
}

/// X2: the four state faces are gallery/sweep entries (and ledger rows, HT side).
@Test func x2StateFacesAreRegistered() {
    let names = Set(ScreenRegistry.entries.map(\.name))
    for face in ScreenStateFaces.registryNames { #expect(names.contains(face), "\(face) missing from ScreenRegistry") }
}

/// W4-2: "Walk me through it again" opened a black cover — the `isPresented` cover's closure read
/// the model `@State` before the write landed. The cover is item-driven, and it gets the real nights.
@Test func w42WalkthroughCoverIsItemDriven() throws {
    let body = try fix5Source("Sources/JIFeatures/GateConfig/GateConfigView.swift")
    #expect(body.contains("onboardingCover(item: $walkthroughModel)"))
    #expect(!body.contains("onboardingCover(isPresented: $showWalkthrough)"))
    #expect(body.contains("makeOnboardingModel(recovery: recoveryInsight?.result)"))
}

/// TR-zones: Training said "HR cap — none set" while the user had 168 bpm + zones.
@Test func trZonesFollowTheUsersSettings() throws {
    let zones = HrZones(anchor: .maxHr, anchorBpm: 190, floorsBpm: [95, 114, 133, 152, 171])
    let set = trainingZoneRows(settings: GateSettings(hrCapBpm: 168, zones: zones))
    #expect(set.first { $0.id == "cap" }?.value == "168 bpm")
    #expect(set.first { $0.id == "z2" }?.value == "114–132")
    #expect(set.first { $0.id == "z5" }?.value == "171–190")
    let none = trainingZoneRows(settings: GateSettings())
    #expect(none.first { $0.id == "cap" }?.value == "— none set")
    #expect(none.first { $0.id == "z2" }?.value == "— none set")
    let body = try fix5Source("Sources/JIFeatures/Training/TrainingView.swift")
    #expect(!body.contains("trainingZoneRows(cap: nil, zone2: nil)"))
    #expect(body.contains("trainingZoneRows(settings: gateSettings)"))
}

/// KPI-sleep-block: "Deep + REM — not read" with deep 3986 s + REM 7672 s on the hub, and
/// "SDNN — not read yet" with the gate's daytime HRV 17.58.
@Test func kpiSleepBlockReadsDeepRemAndSdnn() throws {
    let sleep = try #require(kpiDetailBlock(metric: .sleep, valueText: "82", sleepDuration: "7 h 10", deepRem: "3 h 14"))
    #expect(sleep.rows.first { $0.title == "Deep + REM" }?.value == "3 h 14")
    let hrv = try #require(kpiDetailBlock(metric: .hrv, valueText: "24 ms", sleepDuration: nil, sdnn: "18 ms"))
    #expect(hrv.rows.first { $0.title == "Health app · HRV (SDNN)" }?.value == "18 ms")
    #expect(hrv.rows.first { $0.title == "Daytime HRV" }?.value == "18 ms")
    // Missing stays missing.
    let bare = try #require(kpiDetailBlock(metric: .sleep, valueText: nil, sleepDuration: nil))
    #expect(bare.rows.first { $0.title == "Deep + REM" }?.value == "— not read")

    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-27T08:00:00Z"))
    let days = [RecoveryDay(date: "2026-09-26", deepSleepSec: 3986, remSleepSec: 7672)]
    #expect(kpiDetailDeepRemText(days: days, now: now) == recoverySleepDuration(seconds: 3986 + 7672))
    #expect(kpiDetailDeepRemText(days: [RecoveryDay(date: "2026-09-26", deepSleepSec: 3986)], now: now) == nil)
    #expect(kpiDetailDeepRemText(days: [RecoveryDay(date: "2026-09-20", deepSleepSec: 3986, remSleepSec: 7672)], now: now) == nil)
}

/// KPI-legend: the caption promised a shaded band and a dashed median the chart never drew.
@Test func kpiLegendMarksAreDrawn() throws {
    let parts = try fix5Source("Sources/JIFeatures/Kpi/KpiDetailParts.swift")
    #expect(parts.contains("var normal: PersonalNormalResult?"))
    #expect(parts.contains("RectangleMark("))
    #expect(parts.contains("RuleMark("))
    let view = try fix5Source("Sources/JIFeatures/Kpi/KpiDetailView.swift")
    #expect(view.contains("normal: kpiNormal.normal"))
}

/// Goals-stale: after a PUT of 75.5 the Goals card and More row still said 75.0 — the shell's board
/// read the energy model's goals, which nothing refreshed. A save reports its result.
@Test @MainActor func goalsSaveReportsTheSavedGoals() async throws {
    var reported: Goals?
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), onGoalsSaved: { reported = $0 })
    await vm.load()
    #expect(await vm.save(GoalsUpdate(stepsDaily: 12000)))
    #expect(reported?.stepsDaily == 12000)
    #expect(goalsShown(hub: nil, saved: reported)?.stepsDaily == 12000)

    var failed: Goals?
    let bad = GoalsSetupViewModel(provider: GoalsFakeProvider(updateFails: .network("down")), onGoalsSaved: { failed = $0 })
    #expect(!(await bad.save(GoalsUpdate(stepsDaily: 9000))))
    #expect(failed == nil)
}
