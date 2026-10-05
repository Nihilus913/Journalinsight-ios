import Foundation
import Testing
import UserNotifications
import JICompute
import JIWorkouts
import JIFeatures
@testable import JournalInsight

/// B-43 P3 sim proof (card: "assert pending rest request id, cancel on skip") against the REAL
/// notification centre of the simulator, through the app's one live alert (`RestEndAlert.live`).
/// Opt-in: `TEST_RUNNER_JI_B43_SIM=1 xcodebuild test -scheme JournalInsight
/// -only-testing:JournalInsightTests/B43RestAlertSimTests` on a simulator where the app may post
/// notifications (the prompt was answered Allow once); otherwise `add` is refused and the suite
/// records that instead of a false green.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["JI_B43_SIM"] == "1"))
struct B43RestAlertSimTests {
    private static func pendingRestEnd() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier == RestEndAlert.identifier }
    }

    @Test @MainActor func restStartPlansOnePendingRequestAndSkipCancelsIt() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        try #require(status == .authorized || status == .provisional,
                     "simulator has not allowed notifications for the app (status \(status.rawValue)) — answer the prompt once")
        // Direct add first: surface the centre's own error when it refuses the request.
        let probe = RestEndAlert.request(phase: .resting, endsAt: Date().addingTimeInterval(90), exercise: "probe", now: Date())
        do { try await center.add(probe) } catch { Issue.record("UNUserNotificationCenter.add refused the request: \(error)") }
        center.removePendingNotificationRequests(withIdentifiers: [RestEndAlert.identifier])

        let alert = RestEndAlert.live
        alert.cancel()
        await alert.flush()
        #expect(await Self.pendingRestEnd().isEmpty)

        // Log set → 90 s rest: exactly one pending request, due ~90 s out, deep link to the logger.
        let now = Date()
        alert.sync(SetTimer().startingRest(seconds: 90, at: now), exercise: "Barbell Bench Press", now: now)
        await alert.flush()
        let pending = await Self.pendingRestEnd()
        #expect(pending.count == 1)
        let request = try #require(pending.first)
        #expect(request.content.title == "Rest over 💪")
        #expect(request.content.body == "Next set of Barbell Bench Press — tap to open the logger.")
        #expect(request.content.userInfo[RestEndAlert.deepLinkURLKey] as? String == "ji://strength-log")
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval > 80 && trigger.timeInterval <= 90)

        // +30 s re-plans (still one request, later); Skip cancels it.
        alert.sync(SetTimer().startingRest(seconds: 120, at: now), exercise: "Barbell Bench Press", now: now)
        await alert.flush()
        let replanned = await Self.pendingRestEnd()
        #expect(replanned.count == 1)
        #expect((replanned.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0 > 110)

        alert.sync(SetTimer(), now: now)   // Skip / Dismiss / session end
        await alert.flush()
        #expect(await Self.pendingRestEnd().isEmpty)
    }
}
