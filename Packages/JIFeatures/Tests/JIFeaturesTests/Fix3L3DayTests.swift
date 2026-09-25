import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX3 L3 — BUG-28 (Day vs board 02) and BUG-33 (the Day summary line cut off at AX3).
struct Fix3L3DayTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    // MARK: title line

    @Test func titleLineSaysWhatYouSaidAndWhen() {
        let o = VerdictOverride(date: "2026-09-25", choice: .accept, reason: nil, session: "Day 2 Full Upper",
                                createdAt: "2026-09-25T06:02:11.123456+00:00")
        let v = effectiveVerdictParts(parts: verdictParts("GO — Day 2 Full Upper"), override: o)
        #expect(dayTitleLine(verdict: v, override: o, readiness: 78, timeZone: zurich) == "Full · Day 2 Full Upper · you said Go 08:02")
    }

    @Test func aDifferentCallSaysWhichOne() {
        let o = VerdictOverride(date: "2026-09-25", choice: .rest, reason: "tired", session: "Rest", createdAt: nil)
        let v = effectiveVerdictParts(parts: verdictParts("GO — Day 2 Full Upper"), override: o)
        #expect(dayTitleLine(verdict: v, override: o, readiness: nil, timeZone: zurich).hasSuffix("you picked Rest"))
    }

    @Test func noCallYetKeepsTheReadiness() {
        #expect(dayTitleLine(verdict: verdictParts("GO — Full Upper"), override: nil, readiness: 78, timeZone: zurich)
                == "Full · Full Upper · readiness 78")
    }

    // MARK: sections (the old hero, rings, insight, EA and Mind are gone)

    @Test func dayIsTheBoardsSectionsInOrder() {
        #expect(daySections == [.title, .next, .fuel, .tonight, .squares, .footer])
    }

    // MARK: NEXT card

    @Test func nextCardNamesTheSessionAndSaysWhatIsMissing() {
        let card = dayNextCard(verdict: verdictParts("GO — Full Upper"), sessionForToday: "Day 2 · Full Upper", override: nil)
        #expect(card.session == "Day 2 · Full Upper")
        #expect(card.exercises == "Exercises and weights — No data")
        let rest = dayNextCard(verdict: verdictParts("REST"), sessionForToday: nil, override: nil)
        #expect(rest.session == "Rest day")
        #expect(rest.exercises == nil)
    }

    @Test func anAutoRegulatedDayShowsTheTrimInTheNextCard() {
        let v = verdictParts("GO (auto-regulated) — Day 3 Full Upper + Z2 60min")
        let card = dayNextCard(verdict: v, sessionForToday: nil, override: nil)
        #expect(card.prescription == autoRegulatedPrescription(v))
    }

    // MARK: Fuel today

    private func row(_ date: String, _ values: [String: Double?]) -> DailyKpiRow {
        let json = "{\"date\":\"\(date)\"," + values.map { "\"\($0.key)\":\($0.value.map { "\($0)" } ?? "null")" }.joined(separator: ",") + "}"
        return try! JSONDecoder().decode(DailyKpiRow.self, from: Data(json.utf8))
    }

    @Test func fuelIsTodaysFoodRowWithItsMacros() {
        let daily = [row("2026-09-25", ["kcal_consumed": 640, "kcal_goal": 2100, "protein_g": 48, "carbs_g": 62, "fat_g": 14]),
                     row("2026-09-24", ["kcal_consumed": 1900, "protein_g": 150])]
        let fuel = dayFuel(daily: daily, today: "2026-09-25")
        #expect(fuel.kcal == 640 && fuel.kcalGoal == 2100)
        #expect(fuel.protein == 48 && fuel.carbs == 62 && fuel.fat == 14)
        #expect(fuel.asOf == nil)
    }

    @Test func noFoodTodayIsNotZeroItNamesTheDay() {
        let daily = [row("2026-09-25", ["kcal_consumed": nil, "protein_g": nil]), row("2026-09-24", ["kcal_consumed": 1900, "protein_g": 150])]
        let fuel = dayFuel(daily: daily, today: "2026-09-25")
        #expect(fuel.kcal == 1900)
        #expect(fuel.asOf != nil)
        let none = dayFuel(daily: [], today: "2026-09-25")
        #expect(none.kcal == nil && none.protein == nil)
    }

    @Test func plannedLunchHasNoSourceYet() {
        // W-FIX4 PF-10: the true reason — the hub's meal plan does not reach the phone yet.
        #expect(dayPlannedLunchText == "Planned lunch — meal plan not on the phone yet")
    }

    // MARK: Tonight

    @Test func tonightIsTheSleepGoalAndLastNight() {
        let goal = GateSignal(key: "sleep_h", label: "Sleep time", value: 6.6, unit: "h", threshold: 7, direction: .min,
                              scaleMin: 0, scaleMax: 10, status: .amber, note: nil)
        let now = ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")!
        let t = dayTonight(signals: [goal], recovery: [RecoveryDay(date: "2026-09-25", sleepDurationSec: 23_760)], now: now)
        #expect(t.goalText == "Sleep goal 7 h")
        #expect(t.lastNightText == "Last night 6.6 h")
        let empty = dayTonight(signals: nil, recovery: [], now: now)
        #expect(empty.goalText == "Sleep goal — No data")
        #expect(empty.lastNightText == "Last night — No data")
    }
}
