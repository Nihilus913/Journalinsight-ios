import Foundation
import UserNotifications

/// W2c-L4 — routes a tapped `UNNotification` into the same `DeepLink` pipeline `.onOpenURL`
/// already feeds (`App/Navigation/DeepLink.swift`, frozen W2b-L3 API). Named for the HealthTraining
/// hub's `ntfy` notify sink (`HealthTraining/app/notify/sinks.py`, `HealthTraining CLAUDE.md` §Key
/// paths) whose vocabulary this app's own notifications share, but the ONLY notification source
/// wired up this wave is `LocalVerdictFloor`'s local 05:10 reminder — there is no APNs/remote-push
/// registration in this lane's owned files. A future hub-pushed remote notification that reaches
/// this app (via APNs, not the standalone ntfy Android/iOS app, which is a separate process this app
/// cannot receive taps from) would carry the same `data.url` shape and route through the same pure
/// `deepLink(fromUserInfo:)` below with no changes needed here.
///
/// Split into a pure parsing function + a thin `UNUserNotificationCenterDelegate` shim for the same
/// testability reason as `LocalVerdictFloor`: `UNNotificationResponse` has no public initializer, so
/// a unit test cannot construct one — `deepLink(fromUserInfo:)` takes the plain `[AnyHashable: Any]`
/// the delegate method reads out of `response.notification.request.content.userInfo`, which a test
/// CAN construct directly.
enum NtfyDeepLink {
    /// Pure: resolves a notification's `userInfo` payload (`LocalVerdictFloor.deepLinkURLKey` →
    /// a `ji://…` / `journalinsight://…` string) into a `DeepLink` via the same
    /// `DeepLink.parse(_:)` `.onOpenURL` uses, so a notification tap and a system deep link agree on
    /// every edge case (unknown host, malformed URL, wrong scheme) by construction — there is no
    /// second parser to drift from the frozen one.
    static func deepLink(fromUserInfo userInfo: [AnyHashable: Any]) -> DeepLink? {
        guard let urlString = userInfo[LocalVerdictFloor.deepLinkURLKey] as? String,
              let url = URL(string: urlString) else { return nil }
        return DeepLink.parse(url)
    }
}

/// `UNUserNotificationCenterDelegate` shim: forwards a tapped notification's resolved `DeepLink` to
/// `onDeepLink` (wired by `JournalInsightApp` to its `pendingDeepLink`, the same durable landing spot
/// `.onOpenURL` uses — see that file's doc comment on why cold-start delivery needs one) and lets
/// notifications bank/alert while the app is foregrounded, so the 05:10 floor reminder is visible
/// even if the app happens to be open at 05:10 rather than silently swallowed (`UNUserNotificationCenter`'s
/// default foreground behavior is to suppress presentation).
final class NotificationRoutingDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onDeepLink: (@MainActor (DeepLink) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        defer { completionHandler() }
        guard let link = NtfyDeepLink.deepLink(fromUserInfo: userInfo) else { return }
        let handler = onDeepLink
        Task { @MainActor in
            handler?(link)
        }
    }
}
