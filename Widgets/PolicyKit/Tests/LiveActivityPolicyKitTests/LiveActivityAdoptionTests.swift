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
}
