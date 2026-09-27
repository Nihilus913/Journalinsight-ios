import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// W-FIX5 L3: W5-2, W5-3, W5-4, W3-H2, W3-H4 (docs/audits/2026-09-25-regression-bugs.md).
@MainActor
struct Fix5L3Tests {
    // MARK: W5-2 — a rep range ("6-12") is a target, not "no rep target set"

    @Test func repRangeParsesToItsTop() {
        #expect(progressionRepsTarget("6-12") == 12)
        #expect(progressionRepsTarget("6–12") == 12)   // en dash, as a plan may write it
        #expect(progressionRepsTarget(" 8 - 10 ") == 10)
        #expect(progressionRepsTarget("8") == 8)
        #expect(progressionRepsTarget("max") == nil)
        #expect(progressionRepsTarget(nil) == nil)
        #expect(progressionRepsTarget("12-6") == nil)
    }

    @Test func rangeTargetMakesTheLiftDueWhenEverySetHitsTheTop() {
        let rows = [Exercise(exerciseId: 1, sessionName: "Day 2 Full Upper", exerciseName: "Bench press", sets: 2, repsTarget: "6-12",
                             currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 12)]
        let sets = [LoggedSet(exerciseName: "Bench press", category: nil, setNumber: 1, reps: 12, weightKg: 50),
                    LoggedSet(exerciseName: "Bench press", category: nil, setNumber: 2, reps: 12, weightKg: 50)]
        let out = liftProgressions(exercises: rows, entries: [], lastSessionSets: ["Day 2 Full Upper": sets], autoSuggest: true)
        #expect(out.first?.state == .due(nextKg: 52.5))
        let short = [LoggedSet(exerciseName: "Bench press", category: nil, setNumber: 1, reps: 12, weightKg: 50),
                     LoggedSet(exerciseName: "Bench press", category: nil, setNumber: 2, reps: 9, weightKg: 50)]
        let notYet = liftProgressions(exercises: rows, entries: [], lastSessionSets: ["Day 2 Full Upper": short], autoSuggest: true)
        #expect(notYet.first?.state == .notYet)
    }

    // MARK: W5-3 — no lift weight beside a Rest call

    static let lift = LiftProgression(exerciseId: 1, name: "Bench press", sessionName: "Day 2 Full Upper",
                                      currentKg: 50, nextKg: 50, state: .notYet, sets: 3)

    @Test func restCallHidesTheLiftWeight() {
        let rest = verdictParts("REST — Rest")
        #expect(decideSessionLiftShown(verdict: rest, sessionDetail: "Rest", lifts: [Self.lift]) == nil)
        let go = verdictParts("GO — Day 2 Full Upper")
        #expect(decideSessionLiftShown(verdict: go, sessionDetail: "Rest", lifts: [Self.lift]) == nil)
        #expect(decideSessionLiftShown(verdict: go, sessionDetail: "Day 2 Full Upper", lifts: [Self.lift])?.kg == "50.0 kg")
    }

    @Test func accessibilitySizesStackTheSessionRow() {
        #expect(decideSessionRowStacked(.accessibility3))
        #expect(!decideSessionRowStacked(.large))
    }

    // MARK: W5-4 — Week review opens Your week

    @Test func weekReviewOpensYourWeek() {
        #expect(dayWeekReviewDestination(hasWeekModel: true, hasRationale: true) == .yourWeek)
        #expect(dayWeekReviewDestination(hasWeekModel: false, hasRationale: true) == .rationale)
        #expect(dayWeekReviewDestination(hasWeekModel: false, hasRationale: false) == nil)
    }

    @Test func todayBuildsTheWeekModelOverATrainingProvider() throws {
        let db = try AppDatabase.inMemory()
        let model = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: db))
        model.weekOutbox = { nil }
        #expect(model.makeTrainingWeekModel() != nil)
    }

    // MARK: W3-H2 / W3-H4

    @Test func todayFetchesFortyTwoDays() { #expect(TodayViewModel.trendWindowDays == 42) }

    @Test func galleryDecideAndRationaleShowAScore() throws {
        let result = try #require(RecoveryInsightService.galleryFixture?.result)
        #expect(result.status == .ok)
        #expect(result.score != nil)
        let decide = try #require(TodayViewModel.fixture(morningState: .decide))
        #expect(decideRingScore(readiness: decide.readiness, recovery: result) != nil)
    }
}
