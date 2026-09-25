import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-FIX4 L1 — PF-01 (Decide CTA above the bar), PF-02 (Day NEXT = Training's exercises),
// PF-10 (planned lunch reason), C-f / PF-04 (Decide pill).
struct Fix4L1Tests {
    private func ex(_ id: Int, _ session: String, _ name: String, kg: Double?, sets: Int?, weekday: Int? = nil) -> Exercise {
        Exercise(exerciseId: id, sessionName: session, exerciseName: name, sets: sets, repsTarget: "8",
                 currentWeightKg: kg, progressionStepKg: 2.5, weekday: weekday)
    }

    private var plan: [Exercise] {
        [ex(1, "Day 1 Full Upper", "Barbell Row", kg: 50, sets: 3),
         ex(2, "Day 3 Full Upper", "Barbell Bench Press", kg: 50, sets: 3, weekday: 4),
         ex(3, "Day 3 Full Upper", "Pull-up", kg: 0, sets: 3, weekday: 4)]
    }

    // MARK: PF-02

    @Test func nextCardListsTheSessionsExercisesFromThePlan() {
        let card = dayNextCard(verdict: verdictParts("GO — Day 3 Full Upper"), sessionForToday: "Day 3 Full Upper",
                               override: nil, plan: plan, weekday: nil)
        #expect(card.rows.map(\.name) == ["Barbell Bench Press", "Pull-up"])
        #expect(card.rows.first?.load == "50.0 kg · 3 sets")
        #expect(card.exercises == nil)   // no "No data" line while the rows are there
    }

    @Test func aVerdictSessionWithExtrasStillFindsItsExercises() {
        let card = dayNextCard(verdict: verdictParts("GO (auto-regulated) — Day 3 Full Upper + Z2 60min"), sessionForToday: nil,
                               override: nil, plan: plan, weekday: nil)
        #expect(card.rows.map(\.name) == ["Barbell Bench Press", "Pull-up"])
    }

    @Test func withoutANameMatchTheWeekdaysSessionIsShown() {
        let card = dayNextCard(verdict: verdictParts("GO — Upper"), sessionForToday: nil, override: nil, plan: plan, weekday: 4)
        #expect(card.rows.map(\.name) == ["Barbell Bench Press", "Pull-up"])
    }

    @Test func noPlanRowsSaysSoNeverInvents() {
        let card = dayNextCard(verdict: verdictParts("GO — Day 9 Legs"), sessionForToday: nil, override: nil, plan: plan, weekday: 1)
        #expect(card.rows.isEmpty)
        #expect(card.exercises == "Exercises and weights — \(JIMissingReason.noData.rawValue)")
        let rest = dayNextCard(verdict: verdictParts("REST"), sessionForToday: nil, override: nil, plan: plan, weekday: 4)
        #expect(rest.rows.isEmpty && rest.exercises == nil)
    }

    @Test @MainActor func todayLoadsThePlanItsNextCardReads() async throws {
        let db = try AppDatabase.inMemory()
        let model = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: db), uploadRecord: nil)
        await model.load()
        #expect(model.exercises.contains { $0.exerciseName == "Barbell Bench Press" })
    }

    // MARK: PF-10

    @Test func plannedLunchGivesATrueReason() {
        #expect(!dayPlannedLunchText.contains(JIMissingReason.notInHealthYet.rawValue))
        #expect(dayPlannedLunchText == "Planned lunch — meal plan not on the phone yet")
    }

    // MARK: PF-01

    @Test func decidesActionsArePinnedAboveTheFloatingBar() {
        #expect(decideActionsPinned(offscreen: false))
        #expect(!decideActionsPinned(offscreen: true))   // the sweep keeps them inline in the card
        #expect(decideActionBarBottomClearance(.compact) == tabBarBottomClearance(.compact))
        #expect(decideActionBarBottomClearance(.compact) > 0)
        #expect(decideActionBarBottomClearance(.regular) == 0)
    }
}
