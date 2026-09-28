import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
import JIPersistence
import JISnapshot
@testable import JournalInsight

/// W-FIX7 L1 — F7-1 (S1): a workout in Apple Health today that matches the planned session marks
/// it done on the widget and the Live Activity (which then ends — never refreshed or restarted);
/// a non-matching workout changes nothing on the glances.
@Suite(.serialized)
struct Fix7L1AppTests {
    /// 2026-09-28T05:32:00+02:00.
    private static let now0928: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_790_566_320) }

    private struct Hub0928: HealthDataProvider {
        var capabilities: DataCapability { .hubAll }
        func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
        func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
        func morning() async throws -> MorningResponse {
            try JSON.decoder.decode(MorningResponse.self, from: Data(fix6Morning20260928JSON.utf8))
        }
        func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
        func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
    }

    private struct Workouts: TodayWorkoutsProviding {
        let rows: [TodayWorkout]
        func todayWorkouts() async throws -> [TodayWorkout] { rows }
    }

    private static func workout(_ kind: TodayWorkout.Kind, _ name: String, source: String = "Bevel") -> TodayWorkout {
        let start = now0928().addingTimeInterval(-3600)
        return TodayWorkout(kind: kind, activityName: name, start: start, end: start.addingTimeInterval(52 * 60), sourceName: source)
    }

    private func run(_ rows: [TodayWorkout]) async throws -> (snap: HubSnapshot, updated: [HubSnapshot], finished: [HubSnapshot]) {
        let suite = "ji.test.fix7l1.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(suiteName: suite)
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store, now: Self.now0928)
        env.todayWorkouts = TodayWorkoutsModel(source: Workouts(rows: rows), now: Self.now0928)
        await env.refreshTodayWorkouts()
        var updated: [HubSnapshot] = [], finished: [HubSnapshot] = []
        env.liveActivity = { updated.append($0) }
        env.liveActivityFinish = { finished.append($0) }
        let today = TodayViewModel(provider: Hub0928(), cache: env.cache, prefs: env.prefs, now: Self.now0928, uploadRecord: nil)
        env.bind(today: today, recovery: nil)
        await today.load()
        return (try #require(store.read()), updated, finished)
    }

    @Test @MainActor func matchingStrengthWorkoutMarksTheGlancesDoneAndEndsTheLiveActivity() async throws {
        let r = try await run([Self.workout(.strength, "Traditional strength")])
        #expect(r.snap.verdictSession == "Done · Traditional strength · 52 min · Bevel")
        #expect(r.updated.isEmpty)
        #expect(r.finished.last?.verdictSession == "Done · Traditional strength · 52 min · Bevel")
    }

    @Test @MainActor func nonMatchingWorkoutLeavesTheSessionOpen() async throws {
        let r = try await run([Self.workout(.cardio, "Walk", source: "Workout")])
        #expect(r.snap.verdictSession == "Day 1 Full Upper + Z2 40min")
        #expect(r.finished.isEmpty)
        #expect(r.updated.last?.verdictSession == "Day 1 Full Upper + Z2 40min")
    }

    @Test @MainActor func noWorkoutChangesNothing() async throws {
        let r = try await run([])
        #expect(r.snap.verdictSession == "Day 1 Full Upper + Z2 40min")
        #expect(r.finished.isEmpty)
        #expect(!r.updated.isEmpty)
    }

    @Test func glanceSessionLine() {
        let done = SessionCompletion.done(Self.workout(.strength, "Functional strength"))
        #expect(AppEnvironment.glanceSession(headlineSession: "Strength", completion: done) == "Done · Functional strength · 52 min · Bevel")
        #expect(AppEnvironment.glanceSession(headlineSession: "Strength", completion: .none) == "Strength")
        #expect(AppEnvironment.glanceSession(headlineSession: nil, completion: .none) == "No verdict yet")
    }
}

/// W-FIX7 fixer — AppTests read the sim's real HealthKit through `TodayWorkoutsModel.shared` (126/129
/// while the sim held a workout today); F7-4: the Live Activity waits for the first Health read.
@Suite(.serialized)
struct Fix7FixerAppTests {
    @Test func aUnitTestHostNeverReadsRealHealthWorkouts() {
        #expect(!AppEnvironment.readsHealthWorkouts(arguments: [], environment: ["XCTestConfigurationFilePath": "/x.xctestconfiguration"]))
        #expect(!AppEnvironment.readsHealthWorkouts(arguments: ["-no-healthkit"], environment: [:]))
        #expect(AppEnvironment.readsHealthWorkouts(arguments: [], environment: [:]))
    }

    @Test @MainActor func theTestHostsSharedWorkoutsModelHasNoRealSource() throws {
        _ = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: SnapshotStore(suiteName: "ji.test.fix7fixer.\(UUID().uuidString)"))
        #expect(TodayWorkoutsModel.shared.source == nil)
    }

    private static func snap(word: String = "Go", date: String? = "2026-09-28") -> HubSnapshot {
        HubSnapshot(verdictWord: word, verdictSession: "Day 1", verdictTone: "green", verdictDate: date, readiness: nil, kpis: [], fetchedAt: Date(), lastSync: nil)
    }

    @Test func liveActivityWaitsForTheFirstHealthRead() {
        #expect(AppEnvironment.liveActivityStep(Self.snap(), done: false, workoutsSettled: false) == .none)
        #expect(AppEnvironment.liveActivityStep(Self.snap(), done: true, workoutsSettled: false) == .none)
        #expect(AppEnvironment.liveActivityStep(Self.snap(), done: false, workoutsSettled: true) == .update)
        #expect(AppEnvironment.liveActivityStep(Self.snap(), done: true, workoutsSettled: true) == .finish)
        #expect(AppEnvironment.liveActivityStep(Self.snap(word: "—"), done: true, workoutsSettled: true) == .none)
    }
}
