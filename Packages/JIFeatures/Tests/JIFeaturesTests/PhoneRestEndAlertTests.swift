import Foundation
import Testing
import UserNotifications
import JICore
import JICompute
import JIPersistence
import JIWorkouts
@testable import JIFeatures

/// B-43 P1 — the phone logger's countdown drives the background rest-end alert: a logged set →
/// one pending request at +rest s; +30 s → re-planned at the new end; Skip/Dismiss → none;
/// Complete → none. The request carries `ji://strength-log` so a tap re-opens the logger.
@MainActor
struct PhoneRestEndAlertTests {
    final class Center: RestAlertNotificationCenter, @unchecked Sendable {
        // unchecked: test-only, touched from the MainActor-bound alert chain only.
        var pending: [String: UNNotificationRequest] = [:]
        func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { for id in identifiers { pending[id] = nil } }
        var interval: TimeInterval? { (pending[RestEndAlert.identifier]?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }
    }

    let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    func make(_ center: Center) throws -> (JIFeatures.StrengthLogViewModel, RestEndAlert) {
        let alert = RestEndAlert(center: center)
        let lift = StrengthLogLift(exerciseId: 41, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8", currentKg: 60, stepKg: 2.5, nextKg: 62.5)
        let t0 = self.t0
        let log = JIFeatures.StrengthLogViewModel(lifts: [lift], sessionId: 7, sessionName: "Upper A",
                                                  store: StrengthSessionLogStore(db: try AppDatabase.inMemory()),
                                                  outbox: nil, provider: nil, prefs: nil, today: { "2026-10-05" },
                                                  now: { t0 }, restAlert: alert)
        return (log, alert)
    }

    @Test func loggedSetPlansAddRestReplansSkipCancels() async throws {
        let c = Center(); let (log, alert) = try make(c)
        #expect(log.logSet(exerciseKey: "Barbell Bench Press", weightKg: 62.5, reps: 8) != nil)
        await alert.flush()
        #expect(c.pending.count == 1)
        #expect(c.interval == 90)
        #expect(c.pending[RestEndAlert.identifier]?.content.body.contains("Barbell Bench Press") == true)
        #expect(c.pending[RestEndAlert.identifier]?.content.userInfo["url"] as? String == "ji://strength-log")
        log.timer = log.timer.adding(seconds: 30)       // the view's "+30 s"
        await alert.flush()
        #expect(c.interval == 120)
        log.timer = log.timer.stopped()                 // the view's "Skip"
        await alert.flush()
        #expect(c.pending.isEmpty)
    }

    @Test func completeCancelsThePendingAlert() async throws {
        let c = Center(); let (log, alert) = try make(c)
        _ = log.logSet(exerciseKey: "Barbell Bench Press", weightKg: 62.5, reps: 8)
        await log.complete()
        await alert.flush()
        #expect(c.pending.isEmpty)
    }

    @Test func openRequestIsConsumedOnce() {
        let r = StrengthLoggerOpenRequest()
        #expect(r.consume() == false)
        r.request()
        #expect(r.consume() == true)
        #expect(r.consume() == false)
    }
}
