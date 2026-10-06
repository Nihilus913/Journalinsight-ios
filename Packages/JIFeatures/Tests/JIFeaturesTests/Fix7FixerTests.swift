import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

// W-FIX7 fixer: the verifier's failures on wave/fix7 (F7-2, F7-3, F7-5, N-1, labels, AppTests seam).

private func fixerSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - F7-2: Decide's recovery row gets the hub's recovery (the ring's number)

@Test func f72DecidePassesTheHubsRecoveryToTheRow() throws {
    let decide = try fixerSource("Sources/JIFeatures/Today/DecideView.swift")
    #expect(!decide.contains("RecoveryScoreCard(compact: true)\n"))
    #expect(decide.contains("RecoveryScoreCard(compact: true, hubRecovery: decideHubRecovery(gateSignals)"))   // W-FIX-P2 RG-38: + gateRows
}

// MARK: - F7-3: Apple Health › Readiness = the hub's recovery first

private struct Boom: Error {}

@Test func f73ReadinessLoaderPrefersTheHubsRecovery() async {
    let hubSignals = try? JSON.decoder.decode(MorningResponse.self, from: Data(fix6Morning20260928JSON.utf8)).gateSignals
    let r = await healthReadinessLoad(hubSignals: { hubSignals }, onDevice: { RecoveryScoreResult(status: .ok, score: 37, raw: 37, components: [], nights: 14) })
    #expect(r?.score == 36)
    #expect(healthIsHubReadiness(r))
    #expect(healthComputedTiles(sleepScore: 94, readiness: r)[0].value == "36")
}

@Test func f73ReadinessLoaderFallsBackToTheOnDeviceScore() async {
    var onDeviceCalled = false
    let r = await healthReadinessLoad(hubSignals: { nil }, onDevice: {
        onDeviceCalled = true
        return RecoveryScoreResult(status: .ok, score: 37, raw: 37, components: [RecoveryComponent(key: .hrv, status: .ok, value: 30, z: 0, normalN: 14)], nights: 14)
    })
    #expect(onDeviceCalled)
    #expect(r?.score == 37)
    #expect(await healthReadinessLoad(hubSignals: { nil }, onDevice: { nil }) == nil)
}

@Test func f73AppEnvironmentLoadsReadinessFromTheHubFirst() throws {
    let env = try fixerSource("../../App/AppEnvironment.swift")
    #expect(env.contains("healthReadinessLoad("))
    #expect(env.contains(".morning()"))
}

// MARK: - F7-5: Trends uses the reserved as-of line

@Test func f75TrendsViewDrawsTheReservedAsOfLine() throws {
    let trends = try fixerSource("Sources/JIFeatures/Today/TrendsView.swift")
    #expect(trends.contains("TrendsAsOfLine(card: c, reserve: reserveAsOf)"))
    #expect(trends.contains("trendsReservesAsOfLine("))
    #expect(!trends.contains("if let asOf = c.asOf"))
}

// MARK: - N-1: My KPIs' nutrition squares read Apple Health first

@Test func n1MyKpisNutritionSquaresShowHealthToday() {
    let health = [HealthDailyTotals(date: "2026-09-28", dietaryKcal: 1850, proteinG: 140, carbsG: 180, fatG: 60, fiberG: 30, sugarG: 45)]
    let hub: [KpiMetricId: KpiReading] = [.kcal: KpiReading(value: 1183, date: "2026-09-28"), .protein: KpiReading(value: 98, date: "2026-09-28"),
                                          .carbs: KpiReading(value: 111, date: "2026-09-27"), .fat: KpiReading(value: 38, date: "2026-09-28")]
    let items = kpiCatalogueItems(group: .nutrition, visible: [], value: { hub[$0] }, today: "2026-09-28",
                                  goalCaption: { _, _ in nil }, load: nil, health: health)
    func v(_ id: String) -> Double? { items.first { $0.id == id }?.value }
    #expect(v("kcal") == 1850 && v("protein") == 140 && v("carbs") == 180 && v("fat") == 60)
    #expect(v("fibre") == 30 && v("sugar") == 45)
    // On Today's group too.
    let onToday = kpiCatalogueItems(group: .onToday, visible: [.kcal], value: { hub[$0] }, today: "2026-09-28",
                                    goalCaption: { _, _ in nil }, load: nil, health: health)
    #expect(onToday.first?.value == 1850)
}

@Test func n1HubStaysWhenHealthLacksTheDayOrIsOlder() {
    #expect(kpiHealthFirstReading(.kcal, hub: KpiReading(value: 1183, date: "2026-09-28"), health: []) == KpiReading(value: 1183, date: "2026-09-28"))
    let older = [HealthDailyTotals(date: "2026-09-26", dietaryKcal: 2000)]
    #expect(kpiHealthFirstReading(.kcal, hub: KpiReading(value: 1183, date: "2026-09-28"), health: older)?.value == 1183)
    #expect(kpiHealthFirstReading(.kcal, hub: nil, health: older) == KpiReading(value: 2000, date: "2026-09-26"))
    // Non-nutrition ids are untouched.
    #expect(kpiHealthFirstReading(.hrv, hub: KpiReading(value: 40, date: "2026-09-28"), health: older)?.value == 40)
}

// MARK: - labels

@Test func energyEatenStepNamesAppleHealth() {
    #expect(energyHowWeCalculateSteps[1].title == "Eaten = your Apple Health food total")
    #expect(!energyHowWeCalculateSteps[1].title.contains("YAZIO day total"))
    #expect(energyHowWeCalculateSteps[1].body.contains("YAZIO"))
}

@Test func trainingDayIsNotEmptyWhenHealthHasAWorkout() {
    let w = TodayWorkout(kind: .strength, activityName: "Traditional strength", start: Date(timeIntervalSince1970: 0),
                         end: Date(timeIntervalSince1970: 3600), sourceName: "Health")
    #expect(trainingDayDetailIsEmpty(detail: nil, healthWorkouts: []))
    #expect(!trainingDayDetailIsEmpty(detail: nil, healthWorkouts: [w]))
    #expect(!trainingDayDetailIsEmpty(detail: TrainingDayDetail(date: "2026-09-28", activities: [], exerciseSets: []), healthWorkouts: [w]))
    let card = try? fixerSource("Sources/JIFeatures/Training/TrainingView.swift")
    #expect(card?.contains("healthWorkouts: model.selectedDayHealthWorkouts") == true)
}

// MARK: - F7-4 seam: the glances wait for the first Health read before driving the Live Activity

private struct NoWorkouts: TodayWorkoutsProviding {
    func todayWorkouts() async throws -> [TodayWorkout] { [] }
}

@Test @MainActor func workoutsModelIsSettledOnlyAfterItsFirstRead() async {
    #expect(TodayWorkoutsModel().isSettled)                         // no source: nothing to wait for
    let m = TodayWorkoutsModel(source: NoWorkouts())
    #expect(!m.isSettled)
    await m.refresh()
    #expect(m.isSettled)
}
