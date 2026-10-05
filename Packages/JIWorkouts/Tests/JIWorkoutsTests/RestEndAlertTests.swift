import Foundation
import Testing
import UserNotifications
import JICompute
@testable import JIWorkouts

/// B-43 P1 — fake centre (same shape as JIFeatures' `RemindersFakeCenter`): keeps pending requests
/// by identifier.
final class FakeRestAlertCenter: RestAlertNotificationCenter, @unchecked Sendable {
    // unchecked: test-only, touched from the MainActor-bound alert chain only.
    var pending: [String: UNNotificationRequest] = [:]
    func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending[id] = nil }
    }
    var rest: UNNotificationRequest? { pending[RestEndAlert.identifier] }
    var restInterval: TimeInterval? { (rest?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }
}

@MainActor
struct RestEndAlertTests {
    let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func restStartPlansOneRequestAtTheEnd() async {
        let c = FakeRestAlertCenter(); let a = RestEndAlert(center: c)
        a.sync(SetTimer().startingRest(seconds: 90, at: t0), exercise: "Bench", now: t0)
        await a.flush()
        #expect(c.pending.count == 1)
        #expect(c.restInterval == 90)
        #expect(c.rest?.content.title == "Rest over 💪")
        #expect(c.rest?.content.body.contains("Bench") == true)
        #expect(c.rest?.content.userInfo["url"] as? String == "ji://strength-log")
    }

    @Test func skipRemovesAndAddRestReschedules() async {
        let c = FakeRestAlertCenter(); let a = RestEndAlert(center: c)
        let rest = SetTimer().startingRest(seconds: 60, at: t0)
        a.sync(rest, now: t0)
        a.sync(rest.adding(seconds: 15), now: t0)
        await a.flush()
        #expect(c.pending.count == 1)
        #expect(c.restInterval == 75)
        a.sync(rest.stopped(), now: t0)   // skip — queued right behind the add, never overtaken
        await a.flush()
        #expect(c.pending.isEmpty)
    }

    @Test func unchangedTimerReplansNothingAndElapsedPlansNone() async {
        let c = FakeRestAlertCenter(); let a = RestEndAlert(center: c)
        let rest = SetTimer().startingRest(seconds: 30, at: t0)
        a.sync(rest, now: t0.addingTimeInterval(31))   // already over
        await a.flush()
        #expect(c.pending.isEmpty)
        #expect(a.plannedEnd == nil)
    }

    @Test func timedSetEndCopy() {
        let r = RestEndAlert.request(phase: .timedSet, endsAt: t0.addingTimeInterval(45), exercise: "Plank", now: t0)
        #expect(r.content.title == "Time's up ⏱️")
        #expect(r.content.body == "Plank: hold done — tap to log it.")
        #expect((r.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 45)
        #expect(RestEndAlert.isRestEnd(r))
    }
}

/// The Watch model drives the alert from its countdown.
@MainActor
struct WatchRestAlertTests {
    @MainActor final class Harness {
        let center = FakeRestAlertCenter()
        let h = StrengthLogHarness()
        lazy var alert = RestEndAlert(center: center)
        lazy var vm: StrengthLogViewModel = {
            let vm = StrengthLogViewModel(controller: StrengthWorkoutSessionController(engine: h.engine), bridge: StrengthSessionWatchBridge(transport: h.transport),
                                          clock: { [unowned self] in self.h.now }, restAlert: alert)
            return vm
        }()
        func load() async {
            let plan = StrengthWatchPlan(date: "2026-10-05", planSessionId: 7, title: "Upper A", hrLimitBpm: 175,
                                         exercises: [StrengthLogHarness.bench, StrengthLogHarness.plank])
            h.transport.canSendToRemoteWorkoutSession = true
            try? h.transport.updateApplicationContext([StrengthBridgeKeys.plan: try! JSONEncoder().encode(plan)])
            vm.bridge.receive(applicationContext: h.transport.applicationContext)
            await vm.startSession()
        }
    }

    @Test func loggedSetPlansRestEndSkipCancelsAddRestReschedules() async {
        let x = Harness(); await x.load()
        x.vm.select(StrengthLogHarness.bench)
        await x.vm.logSet()
        await x.alert.flush()
        #expect(x.center.pending.count == 1)
        #expect(x.center.restInterval == 120)   // bench restS
        x.vm.addRest()
        await x.alert.flush()
        #expect(x.center.restInterval == 135)   // +15 s
        x.vm.skipRest()
        await x.alert.flush()
        #expect(x.center.pending.isEmpty)
    }

    @Test func timedSetPlansItsEndAndEndSessionCancels() async {
        let x = Harness(); await x.load()
        x.vm.select(StrengthLogHarness.plank)
        x.vm.startTimedSet()
        await x.alert.flush()
        #expect(x.center.restInterval == 45)
        #expect(x.center.rest?.content.title == "Time's up ⏱️")
        await x.vm.endSession()
        await x.alert.flush()
        #expect(x.center.pending.isEmpty)
    }
}
