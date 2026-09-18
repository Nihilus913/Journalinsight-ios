import Foundation
import Observation
import UIKit
import UserNotifications
import os
import JICore

/// W7-L2 (P-apns-push) — the device end of the hub's APNs channel.
///
/// APNs is **additive**: ntfy stays the primary delivery path (spec L27 "ntfy first") and
/// `LocalVerdictFloor`'s 05:10 local reminder is the no-Mac floor. Nothing here may become a
/// precondition for either — every failure below (simulator with no APNs, authorization denied,
/// hub asleep, wrong `HT_API_TOKEN`) lands in `state` and the log, and the app carries on.
///
/// Shape mirrors `LocalVerdictFloor`: the effectful bits (`UNUserNotificationCenter`,
/// `UIApplication.registerForRemoteNotifications`) are a thin shell around pure builders
/// (`hexToken(from:)`, `appVersion(bundle:)`, `registration(deviceToken:…)`) that tests can call
/// directly — `Data`/`Bundle` are constructible in a test, an APNs token callback is not.
@MainActor
@Observable
final class ApnsRegistration {
    /// Observable, honest state — never a silent "registered" when it isn't (CLAUDE.md rule 5).
    enum State: Equatable {
        /// Nothing attempted yet this launch.
        case idle
        /// The user declined notifications; remote registration is deliberately not attempted.
        case authorizationDenied
        /// `registerForRemoteNotifications()` issued, waiting on the APNs callback.
        case awaitingToken
        /// APNs handed back a token and the hub upserted it.
        case registered(token: String, registeredAt: String)
        /// APNs could not issue a token (simulator, no network, no push profile), or the hub
        /// rejected/could not receive the registration. Carries the reason for the log/debug UI.
        case unavailable(reason: String)
    }

    /// The app-wide instance the `UIApplicationDelegate` token callbacks below reach. A singleton
    /// because `UIApplicationDelegate` methods are the only place APNs hands the token back and
    /// they have no injected context; tests construct their own instance instead and never touch
    /// this one.
    static let shared = ApnsRegistration()

    private(set) var state: State = .idle

    /// Resolved lazily at token time rather than injected once at launch: the hub provider doesn't
    /// exist until `AppEnvironment.apply(_:)` has a `ConnectionConfig` (first run shows the
    /// Connection sheet), and a hub switch replaces it. Returns `nil` when there is no hub-backed
    /// provider to register with — a T2/HealthKit provider (W7-L3) doesn't conform to
    /// `PushTokenProviding`, and that is reported as `.unavailable`, not swallowed.
    var providerSource: (@MainActor () -> (any PushTokenProviding)?)?

    private let logger = Logger(subsystem: "toby913.JournalInsight", category: "apns")

    init() {}

    // MARK: - Pure builders

    /// The `aps-environment` this build is signed with, as the hub's `environment` value. Tracks
    /// `App/JournalInsight.entitlements`, which carries `development` — Xcode's automatic signing
    /// substitutes `production` when archiving for distribution, which is exactly when `DEBUG` is
    /// also off. Kept as a pure mapping over the entitlement string so the rule is testable rather
    /// than a bare `#if` buried in a call site.
    static func environment(apsEnvironment: String?) -> PushEnvironment {
        apsEnvironment == "production" ? .production : .sandbox
    }

    /// The `aps-environment` value compiled into this build. See `environment(apsEnvironment:)`.
    static var apsEnvironmentValue: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    static var currentEnvironment: PushEnvironment { environment(apsEnvironment: apsEnvironmentValue) }

    /// Pure: APNs hands the device token back as raw `Data`; the hub stores and sends it as
    /// lowercase hex. `%02x` (not `String(_, radix: 16)`) so a zero-high-nibble byte keeps both
    /// digits — dropping one would silently produce a token APNs rejects.
    static func hexToken(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Pure: `"<CFBundleShortVersionString> (<CFBundleVersion>)"`, e.g. `"1.0 (42)"`. The hub keeps
    /// this per token so a stale build's token can be told apart after an upgrade. Missing keys
    /// degrade to `"unknown"` rather than crashing a launch path.
    static func appVersion(bundle: Bundle = .main) -> String {
        appVersion(info: { bundle.object(forInfoDictionaryKey: $0) })
    }

    /// Pure core of `appVersion(bundle:)`, taking the Info-dictionary lookup as a closure so a test
    /// can supply missing/partial keys without constructing a `Bundle` (which has no usable public
    /// initializer).
    static func appVersion(info: (String) -> Any?) -> String {
        let short = info("CFBundleShortVersionString") as? String
        let build = info("CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return build
        default: return "unknown"
        }
    }

    /// Pure: the exact body the W7 card's push contract fixes — `token`, `platform`,
    /// `environment`, `app_version`. `ApnsRegistrationTests` encodes this and compares it to a
    /// literal copy of the contract, byte for byte.
    static func registration(
        deviceToken: Data,
        environment: PushEnvironment = ApnsRegistration.currentEnvironment,
        appVersion: String = ApnsRegistration.appVersion()
    ) -> PushTokenRegistration {
        PushTokenRegistration(
            token: hexToken(from: deviceToken),
            platform: .ios,
            environment: environment,
            appVersion: appVersion
        )
    }

    // MARK: - Launch

    /// Called once per cold launch, AFTER `JournalInsightApp`'s existing
    /// `UNUserNotificationCenter.requestAuthorization` — this reuses that one permission flow
    /// rather than prompting a second time. Re-registering every launch is deliberate: APNs may
    /// rotate the token at any time and the hub upserts on `token`, so an unchanged token is a
    /// cheap no-op instead of a duplicate row.
    ///
    /// A denied authorization stops here: registering for remote notifications would still yield a
    /// token, but a time-sensitive alert the user has switched off is not a channel we should claim
    /// to have.
    func registerOnLaunch(
        center: UNUserNotificationCenter = .current(),
        application: UIApplication = .shared
    ) async {
        let status = await center.notificationSettings().authorizationStatus
        guard Self.shouldRegisterForRemoteNotifications(authorizationStatus: status) else {
            state = .authorizationDenied
            logger.notice("APNs: notification authorization denied — ntfy and the local 05:10 floor are unaffected")
            return
        }
        state = .awaitingToken
        application.registerForRemoteNotifications()
    }

    /// Pure decision rule behind `registerOnLaunch`, split out so it is table-testable without a
    /// live `UNUserNotificationCenter` (whose `notificationSettings()` cannot be stubbed —
    /// `UNNotificationSettings` has no public initializer).
    ///
    /// `.denied` is the only stop: `.notDetermined` still registers (the token is useful the moment
    /// the user later allows notifications, and the hub upserts), and `.provisional`/`.ephemeral`
    /// are real delivery states. Registering under `.denied` would give us a token for a channel
    /// the user switched off — a push we'd believe in and they'd never see.
    static func shouldRegisterForRemoteNotifications(authorizationStatus: UNAuthorizationStatus) -> Bool {
        authorizationStatus != .denied
    }

    // MARK: - APNs callbacks

    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. POSTs the token to the
    /// hub per the push contract. A failure is logged and surfaced in `state`; it never throws into
    /// the delegate callback and never blocks anything else.
    func receive(deviceToken: Data) async {
        let registration = Self.registration(deviceToken: deviceToken)
        guard let provider = providerSource?() else {
            state = .unavailable(reason: "no hub provider to register the push token with")
            logger.notice("APNs: token received but no hub connection yet — will re-register on the next launch")
            return
        }
        do {
            let ack = try await provider.registerPushToken(registration)
            state = .registered(token: registration.token, registeredAt: ack.registeredAt)
            logger.notice("APNs: token registered with the hub (\(registration.environment.rawValue, privacy: .public))")
        } catch {
            state = .unavailable(reason: "hub rejected the push token: \(error)")
            logger.error("APNs: push-token registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`. The expected path on the
    /// Simulator (no APNs push profile) — logged as unavailable, explicitly NOT fatal, which is the
    /// W7 close-out's "sim cold-launch OK (APNs registration logged as unavailable on sim)".
    func receiveRegistrationFailure(_ error: Error) {
        state = .unavailable(reason: "APNs registration failed: \(error.localizedDescription)")
        logger.notice("APNs: registration unavailable (\(error.localizedDescription, privacy: .public)) — expected on the Simulator; ntfy is unaffected")
    }
}

/// The APNs token callbacks. An extension on the existing `AppDelegate` (already installed via
/// `@UIApplicationDelegateAdaptor` in `JournalInsightApp`) so this lane adds no second delegate and
/// touches no other lane's file — `UIApplicationDelegate`'s methods are dispatched through the
/// Objective-C runtime, so declaring them here is equivalent to declaring them in the class body.
extension AppDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await ApnsRegistration.shared.receive(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ApnsRegistration.shared.receiveRegistrationFailure(error)
    }
}
