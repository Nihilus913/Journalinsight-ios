import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

struct DaySessionCardTests {
    static func lift(_ id: Int, _ name: String, _ state: ProgressionState, now: Double = 50, next: Double = 50, sets: Int? = 3) -> LiftProgression {
        LiftProgression(exerciseId: id, name: name, sessionName: "Day 2 Full Upper", currentKg: now, nextKg: next, state: state, sets: sets)
    }
    static let lifts = [lift(1, "Bench press", .due(nextKg: 52.5), next: 52.5), lift(2, "Bent-over row", .notYet),
                        lift(3, "Shoulder press", .notYet, now: 12, next: 12), lift(4, "Curl", .noSession, now: 10, next: 10)]
    /// `DailyKpiRow` has only its decoder init — decode the date, then set the column.
    static func kcal(_ date: String, _ v: Double?) -> DailyKpiRow {
        var r = try! JSON.decoder.decode(DailyKpiRow.self, from: Data("{\"date\":\"\(date)\"}".utf8))
        r.values = ["kcal_burned_active": v]
        return r
    }
    static let week = trainingWeekSummary(planSessions: [PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0),
                                                         PlanSessionOut(id: 2, name: "Day 2 Full Upper", weekday: 2),
                                                         PlanSessionOut(id: 3, name: "Day 3 Full Upper", weekday: 4),
                                                         PlanSessionOut(id: 4, name: "Day 4 Full Upper", weekday: 5)],
                                          exercises: [], daily: [Self.kcal("2026-09-21", 400)],
                                          today: "2026-09-23")

    @Test func cardShowsSessionNofNLinesAndCallout() throws {
        let m = try #require(daySessionCardModel(sessionName: "Day 2 Full Upper", lifts: Self.lifts, week: Self.week))
        #expect(m.title == "Day 2 Full Upper, session 2 of 4")
        #expect(m.lines == [DaySessionLine(name: "Bench press", from: "50.0", to: "52.5"), DaySessionLine(name: "Bent-over row", from: nil, to: "50.0")])
        #expect(m.more == "+2 more · 12 sets")
        #expect(m.callout == DaySessionCallout(title: "Progression due on bench press", body: "All sets hit the target reps at 50.0 kg last time."))
    }

    @Test func noSessionNoCard_noDueNoCallout() {
        #expect(daySessionCardModel(sessionName: nil, lifts: Self.lifts, week: Self.week) == nil)
        let m = daySessionCardModel(sessionName: "Day 2 Full Upper", lifts: [Self.lift(2, "Bent-over row", .notYet)], week: nil)
        #expect(m?.title == "Day 2 Full Upper" && m?.callout == nil && m?.more == nil)
    }

    @Test func todaysSessionAndFooter() {
        #expect(todaysStrengthSession(Self.week) == "Day 2 Full Upper")
        #expect(dayWeekFooterText(Self.week) == "Week: 1 of 6 sessions")
        #expect(dayWeekFooterText(nil) == nil)
    }

    @Test func decideLiftShowsNextWeightAndDirection() {
        #expect(decideSessionLift(Self.lifts)! == ("52.5 kg", "↑ Bench up"))
        #expect(decideSessionLift([Self.lift(2, "Bent-over row", .notYet)])! == ("50.0 kg", nil))
        #expect(decideSessionLift([]) == nil)
    }

    // MARK: W-GUI NEXT card wiring

    @Test func nextRowLoadShowsTheStepOnlyWhenDue() {
        let bench = TrainingHeroRow(id: 1, name: "Bench press", load: "50.0 kg · 3 sets")
        let row = TrainingHeroRow(id: 2, name: "Bent-over row", load: "50.0 kg · 3 sets")
        #expect(dayNextRowLoad(bench, lifts: Self.lifts) == ("50.0 → 52.5 kg · 3 sets", true))
        #expect(dayNextRowLoad(row, lifts: Self.lifts) == ("50.0 kg · 3 sets", false))
        #expect(dayNextRowLoad(bench, lifts: []) == ("50.0 kg · 3 sets", false))
        // Hub row names differ from the service's only in case/underscores → still found.
        let garmin = TrainingHeroRow(id: 99, name: "BENCH_PRESS", load: "50.0 kg · 3 sets")
        #expect(dayNextRowLoad(garmin, lifts: Self.lifts).due)
    }

    @Test func weekReviewValueCountsTheWeekOrSaysWhy() {
        #expect(dayWeekReviewValue(Self.week) == "1 of 6 sessions")
        #expect(dayWeekReviewValue(nil) == DayFooterRow.weekReview.value)
        #expect(daySessionOrdinal(Self.week) == "session 2 of 4")
        #expect(daySessionOrdinal(nil) == nil)
    }

    // MARK: DEV-10 — a cardio session gets its own line, never "Exercises and weights — No data"

    @Test func cardioSessionsGetAZone2OrIntervalLine() {
        let zones = HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176])
        #expect(dayCardioLine(session: "Long Zone 2 75-90min", zones: zones, capBpm: nil) == "Zone 2 · 75–90 min · 117–138 bpm")
        #expect(dayCardioLine(session: "Long Zone 2 75-90min", zones: nil, capBpm: 175) == "Zone 2 · 75–90 min · zones not set")
        #expect(dayCardioLine(session: "Norwegian 4x4 intervals", zones: nil, capBpm: nil) == "Intervals · 4 × 4 min")
        #expect(dayCardioLine(session: "Norwegian 4x4 intervals", zones: nil, capBpm: 172) == "Intervals · 4 × 4 min · cap 172 bpm")
        #expect(dayCardioLine(session: "Day 2 Full Upper + Z2 60min", zones: nil, capBpm: nil) == "Zone 2 · 60 min · zones not set")
        #expect(dayCardioLine(session: "Day 2 Full Upper", zones: nil, capBpm: nil) == nil)
        #expect(!daySessionHasStrengthPart("Norwegian 4x4 intervals"))
        #expect(daySessionHasStrengthPart("Day 2 Full Upper + Z2 60min"))
    }

    @Test func cardioNextCardSaysNoNoData() {
        let card = dayNextCard(verdict: verdictParts("GO — Norwegian 4x4 intervals"), sessionForToday: nil, override: nil,
                               plan: [], weekday: 1, zones: nil, capBpm: 175)
        #expect(card.rows.isEmpty)
        #expect(card.exercises == nil)
        #expect(card.cardio == "Intervals · 4 × 4 min · cap 175 bpm")
        // A strength session with no plan rows still says so (PF-02), and keeps its Z2 line.
        let strength = dayNextCard(verdict: verdictParts("GO — Day 9 Legs + Z2 40min"), sessionForToday: nil, override: nil, plan: [], weekday: 1)
        #expect(strength.exercises == "Exercises and weights — \(JIMissingReason.noData.rawValue)")
        #expect(strength.cardio == "Zone 2 · 40 min · zones not set")
        let rest = dayNextCard(verdict: verdictParts("REST"), sessionForToday: nil, override: nil)
        #expect(rest.cardio == nil)
    }

    @Test func nextCardCarriesThePlannedSessionName() {
        let plan = [Exercise(exerciseId: 1, sessionName: "Day 2 Full Upper", exerciseName: "Bench press", sets: 3, repsTarget: "8",
                             currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2)]
        let card = dayNextCard(verdict: verdictParts("GO — Day 2 Full Upper + Z2 60min"), sessionForToday: nil, override: nil, plan: plan, weekday: 2)
        #expect(card.plannedSession == "Day 2 Full Upper")
    }
}
