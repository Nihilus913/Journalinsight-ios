import Foundation
import HealthKit
import Testing
import JICore
import JIFeatures
import JIHealthKit
import JIPersistence
@testable import JournalInsight

/// W-OFFLINE2 OFF2-4 (B-50 slice 2): with no hub the Training tab lists the completed workouts
/// HealthKit holds (history only); the plan, progression and assignment still say "needs the hub".
@Suite @MainActor struct HealthKitTrainingHistoryTests {
    /// The FakeHealthStore of this row: the OFF2-2 seed's five workouts.
    struct FakeHealthStore: HealthStoreWorkoutQuerying, HealthStoreHeartRateQuerying {
        var rows: [HKWorkoutRecord]
        var hr: [HeartRateReading] = []
        func allWorkouts(start: Date, end: Date) async throws -> [HKWorkoutRecord] { rows.filter { $0.start >= start && $0.start < end } }
        func heartRates(start: Date, end: Date) async throws -> [HeartRateReading] { hr.filter { $0.ts >= start && $0.ts <= end } }
    }

    nonisolated static let now = Date(timeIntervalSince1970: 1_791_360_000)   // 2026-10-07 ~ UTC
    static func ago(_ days: Double, _ minutes: Double) -> (Date, Date) {
        let s = now.addingTimeInterval(-days * 86_400 - 3_600 * 3); return (s, s.addingTimeInterval(minutes * 60))
    }
    static var seeded: [HKWorkoutRecord] {
        let r1 = ago(1, 40), w1 = ago(2, 30), s1 = ago(3, 55), r2 = ago(5, 65), w2 = ago(6, 45)
        return [
            HKWorkoutRecord(activityType: .running, start: r1.0, end: r1.1, sourceName: "JI seed", distanceM: 7_200, avgHRBpm: 151),
            HKWorkoutRecord(activityType: .walking, start: w1.0, end: w1.1, sourceName: "JI seed", distanceM: 2_400),
            HKWorkoutRecord(activityType: .traditionalStrengthTraining, start: s1.0, end: s1.1, sourceName: "JI seed", avgHRBpm: 118),
            HKWorkoutRecord(activityType: .running, start: r2.0, end: r2.1, sourceName: "JI seed", distanceM: 12_000, avgHRBpm: 148),
            HKWorkoutRecord(activityType: .walking, start: w2.0, end: w2.1, sourceName: "JI seed", distanceM: 3_600),
        ]
    }
    func history(_ store: FakeHealthStore = FakeHealthStore(rows: seeded)) -> HKTrainingHistoryReader {
        HKTrainingHistoryReader(store: store, heartRate: store, now: { Self.now })
    }
    private func cache() throws -> OfflineCache { OfflineCache(db: try AppDatabase.inMemory()) }

    @Test func noHubTrainingListsTheFiveHealthKitWorkouts() async throws {
        let model = HubScreensFallback.training(source: nil, healthProvider: nil, cache: try cache(), history: history(), now: { Self.now })
        #expect(model.availability == .needsHub)
        #expect(model.hasOnDeviceHistory)
        await model.load()
        #expect(model.phase == .error(NeedsHubCopy.training))   // the plan still needs the hub
        #expect(model.historyLoaded)
        let rows = model.historyWorkouts
        #expect(rows.count == 5)
        #expect(rows.map(\.type) == ["running", "walking", "traditional_strength_training", "running", "walking"])
        #expect(rows.map(\.durationSec) == [2_400, 1_800, 3_300, 3_900, 2_700])
        #expect(rows.map(\.startDate) == Self.seeded.map(\.start))
        #expect(rows.allSatisfy { $0.source == "apple" })
        // Rows with recorded HR open the HR-only detail; the walks without HR are not tappable.
        #expect(rows.map(model.historyRowIsTappable) == [true, false, true, true, false])
    }

    @Test func planReadsStillThrowNeedsHub() async throws {
        let p = OnDeviceTrainingProvider(history: history())
        await #expect(throws: NeedsHubError.self) { try await p.exercises() }
        await #expect(throws: NeedsHubError.self) { try await p.trainingDay(date: "2026-10-06") }
        await #expect(throws: NeedsHubError.self) { try await p.planSessions() }
        await #expect(throws: NeedsHubError.self) { try await p.planWeek(start: "2026-10-05") }
        await #expect(throws: NeedsHubError.self) { try await p.updatePlanSessionWeekday(sessionId: 1, weekday: 2) }
        await #expect(throws: NeedsHubError.self) { try await p.updateExercise(exerciseId: 1, patch: ExerciseUpdate(currentWeightKg: 50, progressionStepKg: 2.5)) }
        #expect(try await p.recentWorkouts(days: 14).count == 5)
    }

    @Test func activityDetailIsHROnlyForAHealthKitWorkout() async throws {
        var store = FakeHealthStore(rows: Self.seeded)
        let run = Self.seeded[0]
        store.hr = (0..<30).map { HeartRateReading(ts: run.start.addingTimeInterval(Double($0) * 60), bpm: 140 + Double($0)) }
        let model = HubScreensFallback.training(source: nil, healthProvider: nil, cache: try cache(), history: history(store), now: { Self.now })
        await model.load()
        let detail = model.makeActivityDetailModel(activity: model.historyWorkouts[0])
        await detail.load()
        guard case .loaded(let series) = detail.phase else { Issue.record("not loaded: \(detail.phase)"); return }
        #expect(series.hrOnly && series.splits.isEmpty && series.points.count == 30)
    }

    @Test func withAHubNothingChanges() throws {
        let hub: any HealthDataProvider = MockDataProvider()
        let model = HubScreensFallback.training(source: hub, healthProvider: hub, cache: try cache(), history: history())
        #expect(model.availability == .live)
        #expect(!model.hasOnDeviceHistory)
        #expect(model.historyWorkouts.isEmpty)
    }

    @Test func noHistorySourceKeepsSliceOneBehaviour() async throws {
        let model = HubScreensFallback.training(source: nil, healthProvider: nil, cache: try cache(), history: nil)
        #expect(!model.hasOnDeviceHistory)
        await model.load()
        #expect(model.phase == .error(NeedsHubCopy.training))
    }
}
