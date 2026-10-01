import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// B-57 W5 Lane B (B1–B3): the Mon–Sun week built from the cached B-52 plan sessions.
@MainActor
struct TrainingWeekPlanTests {
    // Week of Mon 2026-09-21 … Sun 2026-09-27. Gate schedule (JICompute.sessionByWeekday):
    // Tue interval, Thu Z2 long, Sat interval (after 2026-08-30), Sun rest.
    static func ex(_ id: Int, _ session: String, weekday: Int?, sessionId: Int?) -> Exercise {
        Exercise(exerciseId: id, sessionName: session, exerciseName: "Lift \(id)", sets: 3, repsTarget: "8",
                 currentWeightKg: 50, progressionStepKg: 2.5, weekday: weekday, sessionId: sessionId)
    }
    static let plan = [
        PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0),
        PlanSessionOut(id: 2, name: "Day 2 Full Upper", weekday: 2),
        PlanSessionOut(id: 3, name: "Day 3 Full Upper", weekday: 4),
        PlanSessionOut(id: 4, name: "Day 4 Full Upper", weekday: 5),
    ]
    /// `DailyKpiRow` has only its decoder init — decode the date, then set the column.
    static func kcal(_ date: String, _ v: Double?) -> DailyKpiRow {
        var r = try! JSON.decoder.decode(DailyKpiRow.self, from: Data("{\"date\":\"\(date)\"}".utf8))
        r.values = ["kcal_burned_active": v]
        return r
    }

    @Test func lettersFollowAssignmentsThenTheGateSchedule() {
        let s = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [], today: "2026-09-23")
        #expect(s.days.map(\.kind.rawValue) == ["S", "I", "S", "R", "S", "S", "–"])
        #expect(s.days.map(\.date).first == "2026-09-21" && s.days.map(\.date).last == "2026-09-27")
        #expect(s.days[2].isToday && s.days[2].sessionName == "Day 2 Full Upper" && s.days[2].sessionId == 2)
        #expect(s.planTotal == 4 && s.assigned == 4 && s.matchesPlan)
    }

    @Test func doneCountsOnlyStrengthDaysWithTrainingEvidence() {
        let daily = [Self.kcal("2026-09-21", 420), Self.kcal("2026-09-22", 510), Self.kcal("2026-09-23", 120)]
        let s = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: daily, today: "2026-09-23")
        #expect(s.days[0].done == true)
        #expect(s.days[1].done == nil)             // interval day: not a plan session
        #expect(s.days[2].done == nil)             // today, not trained YET — never "missed"
        #expect(s.planDone == 1)
        #expect(s.next?.weekday == 2)              // today's session is next
        #expect(s.nextSessionLabel == "Wed · Day 2 Full Upper")
        #expect(s.doneText == "1 of 4 done")
    }

    @Test func noDailyRowsThisWeekMeansUnknownNotZero() {
        let s = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [Self.kcal("2026-09-14", 600)], today: "2026-09-23")
        #expect(s.planDone == nil)
        #expect(s.doneText == "— of 4 done")
    }

    @Test func pastStrengthDayBelowFloorIsMissed() {
        let s = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [Self.kcal("2026-09-21", 90)], today: "2026-09-23")
        #expect(s.days[0].done == false)
        #expect(s.planDone == 0)
    }

    @Test func twoSessionsOnOneDayAndAnUnassignedOne() {
        let plan = [PlanSessionOut(id: 1, name: "Day 1", weekday: 0), PlanSessionOut(id: 2, name: "Day 2", weekday: 0),
                    PlanSessionOut(id: 3, name: "Day 3", weekday: nil)]
        let s = trainingWeekSummary(planSessions: plan, exercises: [], daily: [Self.kcal("2026-09-21", 400)], today: "2026-09-23")
        #expect(s.days[0].sessionName == "Day 1 + Day 2")
        #expect(s.planTotal == 3 && s.assigned == 2 && !s.matchesPlan)
        #expect(s.planDone == 1)                  // one day done, not two
    }

    @Test func mondayAndSundayBoundaries() {
        let mon = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [], today: "2026-09-21")
        #expect(mon.days.first?.date == "2026-09-21" && mon.days[0].isToday && mon.next?.weekday == 0)
        let sun = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [Self.kcal("2026-09-26", 700)], today: "2026-09-27")
        #expect(sun.days.first?.date == "2026-09-21" && sun.days[6].isToday)
        #expect(sun.next == nil && sun.nextSessionLabel == nil)
    }

    @Test func exercisesAloneStillGiveThePlan() {
        let rows = [Self.ex(1, "Day 1 Full Upper", weekday: 0, sessionId: 1), Self.ex(2, "Day 1 Full Upper", weekday: 0, sessionId: 1),
                    Self.ex(3, "Day 2 Full Upper", weekday: nil, sessionId: nil)]
        let s = trainingWeekSummary(planSessions: [], exercises: rows, daily: [], today: "2026-09-23")
        #expect(s.planTotal == 2 && s.assigned == 1 && s.days[0].kind == .strength)
    }

    @Test func emptyPlanSaysSo() {
        let s = trainingWeekSummary(planSessions: [], exercises: [], daily: [], today: "2026-09-23")
        #expect(s.planTotal == 0 && s.doneText == "No plan yet" && !s.matchesPlan)
    }

    @Test func cachedSummaryReadsTheB52Keys() throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        #expect(TrainingViewModel.cachedWeekSummary(cache: cache, today: "2026-09-23") == nil)
        try cache.put(TrainingViewModel.cacheKeys.planSessions, Self.plan)
        #expect(TrainingViewModel.cachedWeekSummary(cache: cache, today: "2026-09-23")?.planTotal == 4)
    }
}

// B2 — Training "This week" strip.
extension TrainingWeekPlanTests {
    @Test func dayAccessibilityLabelIsWords() {
        let s = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [Self.kcal("2026-09-21", 420)], today: "2026-09-23")
        #expect(trainingWeekDayAccessibilityLabel(s.days[0]) == "Monday, strength, Day 1 Full Upper, done")
        #expect(trainingWeekDayAccessibilityLabel(s.days[2]) == "Wednesday, today, strength, Day 2 Full Upper")
        #expect(trainingWeekDayAccessibilityLabel(s.days[6]) == "Sunday, rest")
        #expect(trainingWeekLegend == "S strength · I intervals · R long run · + library workout")
    }

    /// W-FIX3 BUG-33 carried to the new strip: seven fixed circles stop scaling before AX sizes.
    @Test func weekStripCapsItsTypeSizeBelowAXSizes() {
        #expect(!TrainingThisWeekStrip.maxTypeSize.isAccessibilitySize)
    }
}

// B3 — TrainingWeek screen ("Your week").
extension TrainingWeekPlanTests {
    @Test func summaryStatusWords() {
        let full = trainingWeekSummary(planSessions: Self.plan, exercises: [], daily: [], today: "2026-09-23")
        #expect(trainingWeekStatusText(full) == "Matches plan")
        let short = trainingWeekSummary(planSessions: Self.plan + [PlanSessionOut(id: 5, name: "Day 5", weekday: nil)], exercises: [], daily: [], today: "2026-09-23")
        #expect(trainingWeekStatusText(short) == "1 session not on a day yet")
        let none = trainingWeekSummary(planSessions: [], exercises: [], daily: [], today: "2026-09-23")
        #expect(trainingWeekStatusText(none) == "No plan yet")
    }

    @Test func onlySessionsWithARealIdAreAssignable() {
        let rows = [Self.ex(1, "Day 1", weekday: nil, sessionId: 7), Self.ex(2, "Day 2", weekday: nil, sessionId: nil)]
        #expect(assignableSessions(planSessions: [], exercises: rows).map(\.name) == ["Day 1"])
    }

    /// The HR cap is the user's optional input (W4): an interval row names it only when set.
    @Test func intervalCaptionNamesTheCapOnlyWhenSet() {
        #expect(trainingWeekIntervalCaption(hrCapBpm: 172) == "Your cap 172")
        #expect(trainingWeekIntervalCaption(hrCapBpm: nil) == "No cap set")
    }
}

// W-B40 fixer — B40-V1/V2: the strip follows the plan's own cardio sessions when the hub lists
// them, and shows the library workouts the day sheet shows.
extension TrainingWeekPlanTests {
    static let cardio = [
        PlanSessionOut(id: 5, name: "Interval Run", weekday: 5, sessionType: "cardio"),
        PlanSessionOut(id: 6, name: "Long Zone 2", weekday: 4, sessionType: "cardio"),   // moved Thu → Fri
        PlanSessionOut(id: 7, name: "Rest", weekday: 6, sessionType: "rest"),
    ]
    static let strengthMonWed = [PlanSessionOut(id: 1, name: "Day 1", weekday: 0), PlanSessionOut(id: 2, name: "Day 2", weekday: 2)]

    @Test func knownPlanCardioSessionsReplaceTheFixedSchedule() {
        let s = trainingWeekSummary(planSessions: Self.strengthMonWed, exercises: [], daily: [], today: "2026-09-23",
                                    otherSessions: Self.cardio)
        #expect(s.days.map(\.kind.rawValue) == ["S", "–", "S", "–", "R", "I", "–"])
        #expect(s.days[4].sessionName == "Long Zone 2" && s.days[5].sessionName == "Interval Run")
        #expect(s.planTotal == 2)   // "n of N done" still counts the strength plan
    }

    @Test func libraryWorkoutsOnADayAreOnTheStrip() {
        let sunday = WorkoutTemplate(templateId: 1, name: "Long Run Zone 2", activity: "running", location: .outdoor, weekdays: [6],
                                     steps: [], updatedAt: "2026-09-28T08:00:00Z")
        let linked = WorkoutTemplate(templateId: 2, name: "day 1", activity: "strength", location: .indoor, weekdays: [3],
                                     steps: [], updatedAt: "2026-09-28T08:00:00Z")
        let s = trainingWeekSummary(planSessions: Self.strengthMonWed, exercises: [], daily: [], today: "2026-09-23",
                                    templates: [sunday, linked])
        #expect(s.days[6].extras == ["Long Run Zone 2"])
        #expect(s.days[3].extras.isEmpty)   // named like plan session Day 1 → that session, not an extra
        #expect(trainingWeekDayAccessibilityLabel(s.days[6]).hasSuffix("plus Long Run Zone 2"))
        #expect(trainingWeekDayGlyph(s.days[6]) == "+")
        #expect(trainingWeekDayGlyph(s.days[0]) == "S")
    }
}
