import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// B-89 R-4 — Records VM: hub Garmin history + the phone's own log, computed with OneRepMax.
nonisolated final class RecordsFakeHub: TrainingProviding, @unchecked Sendable { // @unchecked: tests drive it from one actor
    var out: StrengthRecordsOut?
    func trainingDay(date: String) async throws -> TrainingDayDetail { TrainingDayDetail(date: date, activities: [], exerciseSets: []) }
    func exercises() async throws -> [Exercise] { [] }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: false)
    }
    func strengthRecords() async throws -> StrengthRecordsOut {
        guard let out else { throw StrengthRecordsUnavailable() }
        return out
    }
}

@MainActor @Suite(.serialized) struct StrengthRecordsTests {
    private func bench(_ date: String, _ reps: [Int], _ kg: Double = 50) -> StrengthRecordSessionOut {
        StrengthRecordSessionOut(date: date, sets: reps.map { StrengthRecordSetOut(reps: $0, weightKg: kg) }, sources: ["garmin"])
    }

    @Test func mergesHubGarminHistoryWithTheLocalLog() async throws {
        let db = try AppDatabase.inMemory()
        let store = StrengthSessionLogStore(db: db)
        let s = StrengthSessionLog(date: "2026-10-05", startedAt: "2026-10-05T07:00:00Z")
        try store.startSession(s)
        for i in 0..<3 {
            try store.upsertSet(StrengthSetLog(sessionClientId: s.clientId, exerciseKey: "Barbell Bench Press", setIndex: i,
                                               reps: 9, weightKg: 55, performedAt: "2026-10-05T07:0\(i):00Z"))
        }
        let hub = RecordsFakeHub()
        hub.out = StrengthRecordsOut(lifts: [StrengthRecordLiftOut(lift: "Barbell Bench Press", perHand: false, sessions: [
            bench("2026-09-04", [9, 9, 9]), bench("2026-08-03", [12, 10, 10]), bench("2026-07-22", [8, 8, 8])])])
        let model = StrengthRecordsViewModel(store: store, provider: hub, today: { "2026-10-05" })
        await model.load()
        let lift = try #require(model.selectedLift)
        #expect(lift.lift == "Barbell Bench Press")
        #expect(lift.sessions.count == 4)
        #expect(lift.latest?.date == "2026-10-05" && lift.latest?.prs == [.e1rm, .heaviest])
        #expect(lift.records.bestE1rm?.value == 71.5)
        #expect(OneRepMax.status(lift) == .newBest)
        #expect(model.hasGarmin)
        #expect(model.hubError == nil)
    }

    @Test func noHubRouteShowsTheLocalLogOnly() async throws {
        let db = try AppDatabase.inMemory()
        let store = StrengthSessionLogStore(db: db)
        let s = StrengthSessionLog(date: "2026-10-05", startedAt: "2026-10-05T07:00:00Z")
        try store.startSession(s)
        try store.upsertSet(StrengthSetLog(sessionClientId: s.clientId, exerciseKey: "barbell bench press", setIndex: 0,
                                           reps: 8, weightKg: 50, performedAt: "2026-10-05T07:00:00Z"))
        let model = StrengthRecordsViewModel(store: store, provider: RecordsFakeHub(), today: { "2026-10-05" })
        await model.load()
        #expect(model.lifts.map(\.lift) == ["Barbell Bench Press"])
        #expect(!model.hasGarmin && model.hubError == nil)
        #expect(OneRepMax.status(model.lifts[0]) == .first)
        #expect(StrengthRecordsFormat.summary(model.lifts[0]).hasPrefix("One session logged"))
    }

    @Test func formatting() {
        #expect(StrengthRecordsFormat.grouped(1600) == "1 600")
        #expect(StrengthRecordsFormat.setText(.init(reps: 12, weightKg: 50)) == "50 × 12")
        #expect(StrengthRecordsFormat.statusLine(.down(percent: 7)) == "Down 7 % vs your best of the last 4 weeks")
        #expect(StrengthRecordsFormat.weekdayDayMonth("2026-09-04") == "Fri 4 Sep")
    }
}
