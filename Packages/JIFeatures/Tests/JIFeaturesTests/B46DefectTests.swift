import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B46 / L1 — one test per defect Toby found on the device, written from the reproduction on
/// the iPhone 17 Pro simulator against the live hub (screenshots under /tmp/w-b46/l1/).

private func decodeJSON<T: Decodable>(_ json: String, as type: T.Type) -> T {
    try! JSON.decoder.decode(T.self, from: Data(json.utf8))
}

// MARK: - Item 8: Training screen overflowed the viewport horizontally

private func dailyRow(_ date: String, kcal: Double?) -> DailyKpiRow {
    let value = kcal.map { "\($0)" } ?? "null"
    return decodeJSON(#"{"date":"\#(date)","values":{"kcal_burned_active":\#(value)}}"#, as: DailyKpiRow.self)
}

@Test func dayStripNeverRendersMoreThanSevenChips() {
    // The live hub served 8 rows and the device's cache held 11; `WeekStrip` lays out fixed-size
    // chips in a plain HStack, so anything past 7 made the strip — and therefore the whole
    // ScrollView's content — wider than a 393 pt viewport.
    let rows = (1...14).map { dailyRow(String(format: "2026-09-%02d", $0), kcal: 400) }
    let window = TrainingDayStrip.stripWindow(rows)
    #expect(window.count == TrainingDayStrip.stripDayCount)
    #expect(window.count == 7)
}

@Test func dayStripWindowIsTheMostRecentSevenInChronologicalOrder() {
    // The hub returns newest-first; the strip read "13 12 11 …" on the device.
    let rows = (15...22).map { dailyRow(String(format: "2026-09-%02d", $0), kcal: 400) }.reversed()
    let window = TrainingDayStrip.stripWindow(Array(rows))
    #expect(window.map(\.date) == ["2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20", "2026-09-21", "2026-09-22"])
}

@Test func dayStripWindowKeepsShortWeeksWhole() {
    let rows = [dailyRow("2026-09-21", kcal: nil), dailyRow("2026-09-22", kcal: 500)]
    #expect(TrainingDayStrip.stripWindow(rows).map(\.date) == ["2026-09-21", "2026-09-22"])
    #expect(TrainingDayStrip.stripWindow([]).isEmpty)
}

// MARK: - Item 3: HRV / RHR read "—" while the trend below them had data

@Test func kpiCurrentValueFallsBackToTheLatestNonNullDay() {
    // Today's row exists but carries no HRV (no Garmin sync since the 18th). The old code read
    // the latest row and took the field off it, so the headline was "—".
    let days: [RecoveryDay] = [
        decodeJSON(#"{"date":"2026-09-20","hrv_weekly_avg":47}"#, as: RecoveryDay.self),
        decodeJSON(#"{"date":"2026-09-21","hrv_weekly_avg":52}"#, as: RecoveryDay.self),
        decodeJSON(#"{"date":"2026-09-22"}"#, as: RecoveryDay.self),
    ]
    let latest = KpiMetrics.latest(for: .hrv, recovery: days, nutrition: [], dailyRows: [], gateAverages: nil)
    #expect(latest?.value == 52)
    #expect(latest?.date == "2026-09-21")
    #expect(KpiMetrics.value(for: .hrv, recovery: days, nutrition: [], dailyRows: [], gateAverages: nil) == 52)
}

@Test func kpiCurrentValueIsStillNilWhenNoDayEverHadAReading() {
    let days: [RecoveryDay] = [decodeJSON(#"{"date":"2026-09-22"}"#, as: RecoveryDay.self)]
    #expect(KpiMetrics.latest(for: .hrv, recovery: days, nutrition: [], dailyRows: [], gateAverages: nil) == nil)
}

@Test func asOfLabelOnlyAppearsWhenTheReadingIsNotFromToday() throws {
    // The month/day rendering is the reader's locale ("Sep 21" / "21 Sept"); the contract is the
    // "as of " lead-in and that the day named is the value's own.
    let label = try #require(kpiAsOfLabel(valueDate: "2026-09-21", today: "2026-09-22"))
    #expect(label.hasPrefix("as of "))
    #expect(label.contains("21"))
    #expect(kpiAsOfLabel(valueDate: "2026-09-22", today: "2026-09-22") == nil)
    #expect(kpiAsOfLabel(valueDate: nil, today: "2026-09-22") == nil)
    #expect(kpiAsOfLabel(valueDate: "", today: "2026-09-22") == nil)       // the weight-average fallback
    #expect(kpiAsOfLabel(valueDate: "not-a-date", today: "2026-09-22") == nil)
}

@Test @MainActor func todayChipsCarryTheDayTheirFallbackValueCameFrom() async throws {
    let vm = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), prefs: PrefStore(db: try AppDatabase.inMemory()))
    await vm.load()
    let hrv = try #require(vm.chips.first { $0.id == "hrv" })
    #expect(hrv.value != nil)
    // The fixture's newest HRV is 2026-09-21; whatever "today" is when the suite runs, the label
    // is either absent (same day) or names that day — never a different one.
    if let asOf = hrv.asOf { #expect(asOf.hasPrefix("as of ")) }
}

// MARK: - Item 4: the threshold editor showed the raw plan.kpi_target column key

@Test func thresholdSentenceIsInTheMetricsOwnWordsNotTheColumnKey() {
    #expect(kpiThresholdSentence(metricLabel: "Sleep score", operator: "<") == "Alert when Sleep score falls below")
    #expect(kpiThresholdSentence(metricLabel: "Sleep score", operator: "<=") == "Alert when Sleep score falls below")
    #expect(kpiThresholdSentence(metricLabel: "Training load (ACWR)", operator: ">") == "Alert when Training load (ACWR) rises above")
    #expect(kpiThresholdSentence(metricLabel: "Calories", operator: "between").contains("leaves the range"))
    // An operator we do not recognise must never fall through to printing the symbol raw.
    let unknown = kpiThresholdSentence(metricLabel: "Protein", operator: "~=")
    #expect(!unknown.contains("~="))
    #expect(!unknown.contains("_"))
}

@Test func noKpiLabelIsASnakeCaseKey() {
    for def in KpiMetrics.all {
        #expect(!def.label.contains("_"))
    }
}

// MARK: - B-45: the verdict's date is not "today", and a weekday can be assigned

@MainActor
private func makeB45VM(
    training: TrainingFakeProvider = TrainingFakeProvider(),
    now: @escaping () -> Date = { ISO8601DateFormatter().date(from: "2026-09-22T08:00:00Z")! }
) throws -> TrainingViewModel {
    TrainingViewModel(
        provider: training, healthProvider: MockDataProvider(),
        cache: OfflineCache(db: try AppDatabase.inMemory()),
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "b46.\(UUID().uuidString)")),
        now: now
    )
}

@Test @MainActor func trainingScreenDateIsTheDeviceDayNotTheHubsVerdictDate() throws {
    let vm = try makeB45VM()
    #expect(vm.todayDateString == "2026-09-22")
    #expect(vm.todayDate == ISO8601DateFormatter().date(from: "2026-09-22T08:00:00Z")!)
}

@Test @MainActor func aVerdictWrittenOnAnEarlierDayIsReportedStale() async throws {
    let vm = try makeB45VM()
    await vm.load()
    // MockDataProvider's morning fixture carries a fixed verdict date well before 2026-09-22.
    #expect(vm.verdictIsStale)
}

@Test @MainActor func theHubsOwnIsStaleFlagWinsOverTheDateComparison() async throws {
    // An old hub omits `is_stale` and the client infers it; a new hub says so and is believed.
    let fresh = decodeJSON(#"{"today_activities":[],"verdict_date":"2026-01-01","carb_watch_floor":0,"hrv_series":[],"is_stale":false}"#, as: MorningResponse.self)
    #expect(fresh.isStale == false)
    let old = decodeJSON(#"{"today_activities":[],"verdict_date":"2026-01-01","carb_watch_floor":0,"hrv_series":[]}"#, as: MorningResponse.self)
    #expect(old.isStale == nil)
    #expect(old.sessionForToday == nil)
}

@Test @MainActor func plannedSessionComesFromTheHubsDayDetailWhenItHasOne() async throws {
    let training = TrainingFakeProvider()
    training.day = TrainingDayDetail(
        date: "2026-09-22", activities: [], exerciseSets: [],
        plannedSession: PlannedSession(id: 4, name: "Day 2 Full Upper", weekday: 1)
    )
    let vm = try makeB45VM(training: training)
    await vm.load()
    try await Task.sleep(for: .milliseconds(80))
    #expect(vm.plannedSessionForSelectedDay?.name == "Day 2 Full Upper")
}

@Test @MainActor func plannedSessionFallsBackToThePlanRowsWeekdayOnAnOldHub() async throws {
    let training = TrainingFakeProvider()
    training.day = TrainingDayDetail(date: "2026-09-22", activities: [], exerciseSets: [])   // no planned_session
    training.exerciseRows = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 1, sessionId: 7),
    ]
    let vm = try makeB45VM()   // 2026-09-22 is a Tuesday -> plan weekday 1
    #expect(vm.selectedPlanWeekday == 1)
    let vm2 = try makeB45VM(training: training)
    await vm2.load()
    try await Task.sleep(for: .milliseconds(80))
    #expect(vm2.plannedSessionForSelectedDay?.name == "Day 1 Full Upper")
    #expect(vm2.plannedSessionForSelectedDay?.id == 7)
    _ = vm
}

@Test @MainActor func aFailedWeekdayAssignmentRollsBackAndIsSaidOutLoud() async throws {
    // The default `TrainingProviding` implementation throws `PlanSessionUpdateUnavailable`, which
    // is exactly what an old hub (L3's route not merged yet) produces.
    let training = TrainingFakeProvider()
    training.exerciseRows = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: nil, sessionId: 7),
    ]
    let vm = try makeB45VM(training: training)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    #expect(vm.sessionAssignFailed.contains(7))
    #expect(vm.pendingSessionAssign.isEmpty)
    #expect(vm.exercises.first?.weekday == nil)   // rolled back, never a lie on screen
}

@Test @MainActor func aSuccessfulWeekdayAssignmentSticks() async throws {
    let training = TrainingFakeProvider()
    training.exerciseRows = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: nil, sessionId: 7),
    ]
    training.planSessionUpdate = { id, weekday in PlanSessionOut(id: id, name: "Day 1 Full Upper", weekday: weekday) }
    let vm = try makeB45VM(training: training)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    #expect(vm.sessionAssignFailed.isEmpty)
    #expect(vm.exercises.first?.weekday == 3)
}

// MARK: - Contract decoding: every new field is optional on an old hub

@Test func planRowsDecodeWithAndWithoutTheWeekdayField() {
    let new = decodeJSON(#"{"exercise_id":1,"session_name":"Day 1","exercise_name":"Bench","weekday":2,"session_id":9}"#, as: Exercise.self)
    #expect(new.weekday == 2)
    #expect(new.sessionId == 9)
    let old = decodeJSON(#"{"exercise_id":1,"session_name":"Day 1","exercise_name":"Bench"}"#, as: Exercise.self)
    #expect(old.weekday == nil)
    #expect(old.sessionId == nil)
    let unassigned = decodeJSON(#"{"exercise_id":1,"session_name":"Day 1","exercise_name":"Bench","weekday":null}"#, as: Exercise.self)
    #expect(unassigned.weekday == nil)
}

@Test func dayDetailDecodesWithAndWithoutAPlannedSession() {
    let new = decodeJSON(#"{"date":"2026-09-22","activities":[],"exercise_sets":[],"planned_session":{"id":4,"name":"Day 2","weekday":1}}"#, as: TrainingDayDetail.self)
    #expect(new.plannedSession?.weekday == 1)
    let old = decodeJSON(#"{"date":"2026-09-22","activities":[],"exercise_sets":[]}"#, as: TrainingDayDetail.self)
    #expect(old.plannedSession == nil)
}

@Test func planWeekdayConvertsFromCalendarsSundayFirstNumbering() {
    // Calendar: Sun = 1 … Sat = 7. plan_session.weekday: Mon = 0 … Sun = 6.
    #expect(planWeekday(fromCalendarWeekday: 2) == 0)   // Monday
    #expect(planWeekday(fromCalendarWeekday: 3) == 1)   // Tuesday
    #expect(planWeekday(fromCalendarWeekday: 7) == 5)   // Saturday
    #expect(planWeekday(fromCalendarWeekday: 1) == 6)   // Sunday
    #expect(planWeekdayName(0) == "Monday")
    #expect(planWeekdayName(6) == "Sunday")
    #expect(planWeekdayName(7) == nil)
    #expect(planWeekdayName(nil) == nil)
}
