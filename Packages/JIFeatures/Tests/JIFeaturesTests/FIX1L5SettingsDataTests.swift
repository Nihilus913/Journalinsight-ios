import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX1 L5 — Settings data rows (BUG-10, 11, 23, 24, 50 in
// HealthTraining docs/audits/2026-09-25-regression-bugs.md).

private func fresh(_ source: String, _ dso: Int, _ metric: String, _ state: FreshnessState, _ days: Int?) -> FreshnessEntry {
    FreshnessEntry(source: source, dsoKey: dso, metric: metric, metricLabel: metric, state: state, lastDate: nil,
                   firstDate: nil, daysStale: days, cadenceDays: 1, coverageChecked: true, gaps: nil,
                   gapCount: nil, totalMissingDays: nil)
}

/// The live `/ingestion/freshness` shape of 2026-09-25 (cons/ingestion_freshness.json), trimmed to
/// what the summary reads.
private let liveFreshness: [FreshnessEntry] = [
    fresh("GarminAPI", 2, "activity", .red, 21),
    fresh("GarminDB", 1, "activity_summary", .red, 178),
    fresh("AppleHealth", 4, "body", .red, 491),
    fresh("GarminAPI", 2, "recovery", .red, 4),
    fresh("GarminDB", 1, "recovery", .red, 4),
    fresh("GarminAPI", 2, "sleep", .red, 13),
    fresh("GarminDB", 1, "sleep", .red, 179),
    fresh("GarminDB", 1, "training_load", .red, 178),
    fresh("GarminDB", 1, "vitals", .red, 178),
    fresh("GarminAPI", 2, "activity_summary", .amber, 3),
    fresh("GarminAPI", 2, "vitals", .amber, 3),
    fresh("GarminAPI", 2, "vo2max", .amber, 22),
    fresh("AppleHealth", 4, "activity_summary", .green, 1),
    fresh("YAZIO", 3, "body", .green, 0),
    fresh("YAZIO", 3, "nutrition", .green, 0),
    fresh("AppleHealth", 4, "sleep", .green, 1),
    fresh("GarminAPI", 2, "training_load", .green, 0),
    fresh("AppleHealth", 4, "vitals", .green, 1),
]

// MARK: BUG-10 — a source row states that source's freshness

@Test func bug10AppleIsFreshWhenItsDeliveredMetricsAreFresh() {
    let s = dataQualityBoardSourceSummary(liveFreshness)
    let apple = s.sources.first { $0.source == "Apple Watch" }
    #expect(apple?.state == .green)          // not "Stale 491 d" from the unused Apple weight
    // W-FIX4 PF-11: Garmin's row is its feed's freshness (vitals / activity summary 3 d), not its
    // worst metric (Activities 21 d) — still stale (amber), never "Stale 21 d".
    let garmin = s.sources.first { $0.source == "Garmin" }
    #expect(garmin?.state == .amber)
    #expect(garmin?.daysStale == 3)
    #expect(s.sources.count == 3)            // retired GarminDB is not a fourth stale source
    #expect(s.fresh == 2)
    #expect(s.stale == 1)
}

@Test func bug10RetiredGarminDBNeverCountsAsStale() {
    let s = dataQualityBoardSourceSummary([fresh("GarminDB", 1, "sleep", .red, 179),
                                           fresh("AppleHealth", 4, "sleep", .green, 1)])
    #expect(s.sources.map(\.source) == ["Apple Watch"])
    #expect(s.stale == 0)
}

@Test @MainActor func bug10ViewModelSummaryUsesTheBoardRule() async {
    let report = DataQualityReport(generatedAt: "2026-09-25T08:27:48Z", qualityScore: [], freshness: liveFreshness, sourceTrust: [], provenanceGap: "")
    let vm = DataQualityViewModel(provider: FixedDQProvider(report: report))
    await vm.load()
    #expect(vm.sourceSummary.stale == 1)
    #expect(vm.sourceSummary.sources.count == 3)
}

private struct FixedDQProvider: DataQualityProviding {
    let report: DataQualityReport
    func dataQuality() async throws -> DataQualityReport { report }
}

// MARK: BUG-50 — board names, never raw hub ids

@Test func bug50SourceRowsUseBoardNames() {
    let names = dataQualityBoardSourceSummary(liveFreshness).sources.map { dataQualitySourceDisplay($0.source) }
    #expect(names.contains("Apple Watch"))
    #expect(names.contains("Garmin"))
    #expect(!names.contains { ["AppleHealth", "GarminAPI", "GarminDB"].contains($0) })
    #expect(dataQualitySourceDisplay("AppleHealth") == "Apple Watch")
    #expect(dataQualitySourceDisplay("GarminAPI") == "Garmin")
    #expect(dataQualitySourceDisplay("GarminDB") == "Garmin")
}

// MARK: BUG-23 — the hub's `str(timestamptz)` last sync parses

@Test func bug23ParsesPostgresTimestampWithOffset() {
    let d = parseHubTimestamp("2026-09-25 10:02:23.725876+02:00")
    #expect(d != nil)
    #expect(d.map { abs($0.timeIntervalSince1970 - 1_790_323_343.725) < 1 } == true)  // 08:02:23Z
    #expect(parseHubTimestamp("2026-09-25 10:02:23+02:00") != nil)
    #expect(parseHubTimestamp("2026-09-25 08:02:23.725876+00") != nil)
    #expect(formatSyncFreshness("2026-09-25 10:02:23.725876+02:00",
                                now: Date(timeIntervalSince1970: 1_790_323_344 + 600)) == "Synced 10m ago")
}

// MARK: BUG-11 — next working weight reads strength_state from the hub

private nonisolated struct GoalsAndTrainingProvider: GoalsSetupProviding, TrainingProviding {
    let inner = MockDataProvider()
    let rows: [Exercise]
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { try await inner.goals() }
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals { try await inner.updateGoals(patch) }
    func trainingDay(date: String) async throws -> TrainingDayDetail { try await inner.trainingDay(date: date) }
    func exercises() async throws -> [Exercise] { rows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
}

private let hubExercises: [Exercise] = [
    Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Barbell Bench Press", sets: 3,
             repsTarget: "6-12", currentWeightKg: 50, progressionStepKg: 2.5),
    Exercise(exerciseId: 20, sessionName: "Day 1 Full Upper", exerciseName: "Barbell Row", sets: 3,
             repsTarget: "6-12", currentWeightKg: 50, progressionStepKg: 2.5),
    Exercise(exerciseId: 21, sessionName: "Day 1 Full Upper", exerciseName: "DB Shoulder Press", sets: 3,
             repsTarget: "12", currentWeightKg: 12, progressionStepKg: 2.5),
    Exercise(exerciseId: 24, sessionName: "Day 1 Full Upper", exerciseName: "Dead Bug", sets: 3,
             repsTarget: "10/side", currentWeightKg: nil, progressionStepKg: nil),
]

@Test @MainActor func bug11GoalsSetupReadsHubStrengthState() async {
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "fix1.l5.\(UUID().uuidString)"))
    let vm = GoalsSetupViewModel(provider: GoalsAndTrainingProvider(rows: hubExercises), strengthStore: store)
    #expect(vm.nextWorkingWeights.allSatisfy { $0.kg == nil })
    await vm.load()
    #expect(vm.nextWorkingWeights.map(\.name) == ["Bench press", "Bent-over row"])
    #expect(vm.nextWorkingWeights.map(\.kg) == [50, 50])
    // Mirrored for offline: a fresh model on the same store still knows it.
    let offline = GoalsSetupViewModel(provider: GoalsFakeProvider(), strengthStore: store)
    #expect(offline.nextWorkingWeights.map(\.kg) == [50, 50])
}

@Test func bug11HubNamesMatchTheBoardRows() {
    let entries = [
        StrengthStateEntry(exerciseId: 19, exerciseName: "Barbell Bench Press", currentWeightKg: 52.5,
                           progressionStepKg: 2.5, sets: 3, repsTarget: nil, updatedAt: "2026-09-25T08:00:00Z", synced: true),
        StrengthStateEntry(exerciseId: 20, exerciseName: "Barbell Row", currentWeightKg: 47.5,
                           progressionStepKg: 2.5, sets: 3, repsTarget: nil, updatedAt: "2026-09-25T08:00:00Z", synced: true),
        StrengthStateEntry(exerciseId: 21, exerciseName: "DB Shoulder Press", currentWeightKg: 12,
                           progressionStepKg: 2.5, sets: 3, repsTarget: nil, updatedAt: "2026-09-25T08:00:00Z", synced: true),
    ]
    #expect(nextWorkingWeights(entries: entries).map(\.kg) == [52.5, 47.5])
}

@Test func bug11MirrorKeepsAnUnsyncedLocalEdit() {
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "fix1.l5.\(UUID().uuidString)"))
    store.saveLocal(exerciseId: 19, exerciseName: "Barbell Bench Press",
                    patch: ExerciseUpdate(currentWeightKg: 55, progressionStepKg: 2.5))
    store.mirrorHub(hubExercises)
    #expect(store.getLocal(exerciseId: 19)?.currentWeightKg == 55)   // offline edit not clobbered
    #expect(store.getLocal(exerciseId: 20)?.currentWeightKg == 50)
    #expect(store.getLocal(exerciseId: 20)?.synced == true)
    #expect(store.getLocal(exerciseId: 24) == nil)                    // no weight → nothing invented
}

// MARK: BUG-24 — KPI targets mirror reads the persisted copy

@Test @MainActor func bug24KpiTargetsMirrorReadsThePersistedCache() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put(localMirrorsKpiTargetsCacheKey, [KpiTarget(targetId: 1, metric: "steps", operator: ">=", threshold: 10000)])
    let vm = LocalMirrorsViewModel(targets: [], targetsCache: cache, decisionLog: nil)
    await vm.load()
    #expect(vm.targets.count == 1)
    #expect(localMirrorsKpiTargetsCacheKey == "kpi.targets")   // the key KpiListViewModel writes
}
