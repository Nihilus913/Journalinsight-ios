import Foundation
import UserNotifications

/// W7-L2 (P-apns-push) — resolves a *remote* (APNs) notification's custom data into a `DeepLink`.
///
/// The hub's `ApnsSink` (W7-L1) sends custom data `{"deeplink": "ji://gate?date=YYYY-MM-DD"}` —
/// the same string `_ji_click_url()` already builds for the ntfy click action
/// (`HealthTraining/scripts/morning_go.py`), under a different key (`deeplink`, not ntfy's `url`).
/// That single key difference is the ONLY thing this type knows: the URL itself is handed straight
/// to `NtfyDeepLink.deepLink(fromUserInfo:)`, which is the frozen `DeepLink.parse(_:)` seam, so an
/// APNs tap and an ntfy tap agree on every edge case (unknown host, malformed URL, wrong scheme,
/// the `?date=` query `DeepLink.gate` ignores) by construction. There is no second parser here.
///
/// `resolve(userInfo:)` is the one entry point `NotificationRoutingDelegate` calls, and it tries
/// the APNs key first, then falls back to the ntfy/local key — so `LocalVerdictFloor`'s 05:10
/// reminder keeps routing exactly as it did before this lane (its payload has no `deeplink` key,
/// so the first lookup misses and the fallback is the unchanged call).
enum ApnsPayloadRouter {
    /// The APNs custom-data key, fixed by the W7 card's push contract. Must stay byte-identical
    /// to the key the hub's `ApnsSink` writes.
    static let deepLinkKey = "deeplink"

    /// Pure: an APNs payload's `deeplink` string → `DeepLink`, or `nil` when the key is absent,
    /// not a string, or not a link this app understands.
    static func deepLink(fromApnsUserInfo userInfo: [AnyHashable: Any]) -> DeepLink? {
        guard let urlString = userInfo[deepLinkKey] as? String else { return nil }
        return NtfyDeepLink.deepLink(fromUserInfo: [LocalVerdictFloor.deepLinkURLKey: urlString])
    }

    /// Pure: the single resolver for EVERY notification tap, remote or local. APNs custom data
    /// first, then the local/ntfy `url` key. Returning `nil` means "no destination" — the tap
    /// still opens the app, it just doesn't navigate (never a guessed destination).
    static func resolve(userInfo: [AnyHashable: Any]) -> DeepLink? {
        deepLink(fromApnsUserInfo: userInfo) ?? NtfyDeepLink.deepLink(fromUserInfo: userInfo)
    }
}
