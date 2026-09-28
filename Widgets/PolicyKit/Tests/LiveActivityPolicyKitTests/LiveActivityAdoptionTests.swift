import Foundation
import Testing
@testable import LiveActivityPolicyKit

/// W-FIX7 F7-4: every launch started a new verdict activity and stacked duplicates on the Lock
/// Screen. The controller now adopts a running one and ends any extra — never a second card.
@Suite struct LiveActivityAdoptionTests {
    @Test func noneRunningStartsFresh() {
        let plan = LiveActivityAdoption.plan(running: [(id: String, isActive: Bool)]())
        #expect(plan.adopt == nil)
        #expect(plan.end.isEmpty)
    }

    @Test func adoptsTheFirstActiveAndEndsTheDuplicates() {
        let plan = LiveActivityAdoption.plan(running: [(id: "a", isActive: false), (id: "b", isActive: true), (id: "c", isActive: true), (id: "d", isActive: true)])
        #expect(plan.adopt == "b")
        #expect(plan.end == ["c", "d"])
    }

    @Test func endedActivitiesAreNeverAdopted() {
        let plan = LiveActivityAdoption.plan(running: [(id: "a", isActive: false)])
        #expect(plan.adopt == nil)
        #expect(plan.end.isEmpty)
    }

    // W-FIX7 fixer F7-4: ended ("Done") cards stacked, one per relaunch. Keep today's newest ended
    // card, dismiss every other ended one, and never request a new card on a day that already ended.
    private static let day = Date(timeIntervalSince1970: 1_790_566_320)          // 2026-09-28 05:32 +02:00
    private static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Zurich")!; return c }

    @Test func endedCardsKeepTodaysNewestAndDismissTheRest() {
        let plan = LiveActivityAdoption.endedPlan(ended: [(id: "a", lastUpdate: Self.day.addingTimeInterval(600)),
                                                          (id: "b", lastUpdate: Self.day.addingTimeInterval(1200)),
                                                          (id: "c", lastUpdate: Self.day.addingTimeInterval(-86_400))],
                                                  now: Self.day.addingTimeInterval(3600), calendar: Self.cal)
        #expect(plan.keep == "b")
        #expect(Set(plan.dismiss) == ["a", "c"])
        #expect(plan.dayFinished)
    }

    @Test func noEndedCardTodayLetsANewOneStart() {
        let plan = LiveActivityAdoption.endedPlan(ended: [(id: "c", lastUpdate: Self.day.addingTimeInterval(-86_400))],
                                                  now: Self.day, calendar: Self.cal)
        #expect(plan.keep == nil)
        #expect(plan.dismiss == ["c"])
        #expect(!plan.dayFinished)
        #expect(!LiveActivityAdoption.endedPlan(ended: [(id: String, lastUpdate: Date)](), now: Self.day, calendar: Self.cal).dayFinished)
    }
}
