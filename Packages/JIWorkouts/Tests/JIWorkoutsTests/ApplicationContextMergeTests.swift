import Foundation
import Testing
@testable import JIWorkouts

/// W-B78 B78-1: `updateApplicationContext` REPLACES the whole dict — the strength plan and the
/// HubSnapshot share it, so every sender merges one key and keeps the rest.
@MainActor
@Suite
struct ApplicationContextMergeTests {
    private let plan = StrengthWatchPlan(date: "2026-10-06", planSessionId: 9, title: "Upper A", hrLimitBpm: 175, exercises: [])
    private let snapshotBytes = Data(#"{"verdictWord":"GO"}"#.utf8)

    @Test func snapshotKeyMatchesTheWire() { #expect(StrengthBridgeKeys.snapshot == "ji.snapshot") }

    @Test func mergeKeepsOtherKeys() throws {
        let t = FakeStrengthBridgeTransport()
        try t.mergeApplicationContext(key: "a", value: Data([1]))
        try t.mergeApplicationContext(key: "b", value: Data([2]))
        try t.mergeApplicationContext(key: "a", value: Data([3]))
        #expect(t.applicationContext["a"] as? Data == Data([3]))
        #expect(t.applicationContext["b"] as? Data == Data([2]))
        #expect(t.applicationContext.count == 2)
    }

    @Test func planSurvivesASnapshotPush() throws {
        let t = FakeStrengthBridgeTransport()
        let phone = StrengthSessionPhoneBridge(transport: t, sink: NoSink())
        try phone.sendPlan(plan)
        try t.mergeApplicationContext(key: StrengthBridgeKeys.snapshot, value: snapshotBytes)
        #expect(t.applicationContext[StrengthBridgeKeys.snapshot] as? Data == snapshotBytes)
        let planData = try #require(t.applicationContext[StrengthBridgeKeys.plan] as? Data)
        #expect(try JSONDecoder().decode(StrengthWatchPlan.self, from: planData) == plan)
        // and the watch side still reads the plan out of the merged context
        let watch = StrengthSessionWatchBridge(transport: FakeStrengthBridgeTransport())
        watch.receive(applicationContext: t.applicationContext)
        #expect(watch.plan == plan)
    }

    @Test func snapshotSurvivesAPlanPush() throws {
        let t = FakeStrengthBridgeTransport()
        try t.mergeApplicationContext(key: StrengthBridgeKeys.snapshot, value: snapshotBytes)
        try StrengthSessionPhoneBridge(transport: t, sink: NoSink()).sendPlan(plan)
        #expect(t.applicationContext[StrengthBridgeKeys.snapshot] as? Data == snapshotBytes)
        #expect(t.applicationContext[StrengthBridgeKeys.plan] is Data)
    }

    @Test func routerSplitsPlanAndSnapshot() {
        var plans: [Data] = [], snaps: [Data] = []
        let ctx: [String: Any] = [StrengthBridgeKeys.plan: Data([1]), StrengthBridgeKeys.snapshot: Data([2]), "other": 3]
        StrengthBridgeContextRouter.route(ctx, plan: { plans.append($0[StrengthBridgeKeys.plan] as! Data) }, snapshot: { snaps.append($0) })
        #expect(plans == [Data([1])])
        #expect(snaps == [Data([2])])
        StrengthBridgeContextRouter.route([StrengthBridgeKeys.snapshot: Data([4])], plan: { _ in plans.append(Data()) }, snapshot: { snaps.append($0) })
        #expect(plans.count == 1)
        #expect(snaps == [Data([2]), Data([4])])
    }
}

@MainActor
private final class NoSink: StrengthSessionLogSink {
    func bridgeSessionStarted(_ start: StrengthBridgeSessionStart) async {}
    func bridgeSetLogged(_ set: StrengthBridgeSet) async {}
    func bridgeSetEdited(_ set: StrengthBridgeSet) async {}
    func bridgeSetDeleted(clientId: UUID, sessionClientId: UUID) async {}
    func bridgeSessionEnded(_ end: StrengthBridgeSessionEnd) async {}
}
