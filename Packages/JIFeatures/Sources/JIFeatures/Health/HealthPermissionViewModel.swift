import Foundation
import Observation
import JICore
import JIHealthKit
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

// `HKPermission` is JIHealthKit's (`HealthKitPermissions.swift`) — W8-L4 (B-12) deleted the
// same-named duplicate that used to live here (W2d built it against the card's NAME because the
// two lanes ran in parallel), so there is exactly one three-state read-permission type app-wide
// and `AppEnvironment` no longer maps between two enums case by case.

/// Drives the "Connect Apple Health" permission flow and which T2 (Apple Watch) tiles are gated
/// (W2d, L3). Built against JIHealthKit's `HKPermission` and the plain `DataCapability` bitmap
/// (JICore).
@Observable @MainActor
public final class HealthPermissionViewModel {
    public private(set) var permission: HKPermission

    /// What Apple Watch (HealthKit) can supply on this device/OS — the T2 set (wave card: SDNN
    /// yes; RMSSD only when the iOS 27 type exists; never bodyBattery/trainingReadiness/
    /// garminSleepScore). `AppEnvironment` injects L1's real `appleWatchCapabilities`; this
    /// default (SDNN only) stands in for previews and any test that doesn't override it.
    public let appleWatchCapabilities: DataCapability

    /// W-DATA R3 (DEV-14): the hub's Apple-night sleep score (`/vitals/sleep-summary`
    /// `score_computed`) for the "Computed from these" tile; nil = "—".
    public private(set) var sleepScore: Double?

    private let requestPermission: () async -> HKPermission
    private let openHealthSettings: @MainActor () -> Void
    private let loadSleepScore: (@Sendable () async -> Double?)?

    public init(
        permission: HKPermission = .notDetermined,
        appleWatchCapabilities: DataCapability = [.hrvSDNN],
        requestPermission: @escaping () async -> HKPermission,
        openHealthSettings: @escaping @MainActor () -> Void = HealthPermissionViewModel.openHealthSettingsOnDevice,
        loadSleepScore: (@Sendable () async -> Double?)? = nil
    ) {
        self.permission = permission
        self.appleWatchCapabilities = appleWatchCapabilities
        self.requestPermission = requestPermission
        self.openHealthSettings = openHealthSettings
        self.loadSleepScore = loadSleepScore
    }

    /// DEV-12: the user has answered the sheet (or data arrived). iOS never shows the sheet again
    /// for a decided type, so the button must lead to where access is changed instead.
    public var isDecided: Bool { permission != .notDetermined }

    public var connectLabel: String { isDecided ? "Open Health settings" : "Connect Apple Health" }

    /// The primary button. Undecided: the injected permission request, adopting whatever
    /// three-state result comes back (never assumes success). Decided: opens Health's sharing
    /// settings (DEV-12 — the request call is a silent no-op there, the old "dead button").
    public func connect() async {
        guard !isDecided else { openHealthSettings(); return }
        permission = await requestPermission()
    }

    /// DEV-12: data ARRIVING at the hub proves a read grant — HealthKit never reports one. Any
    /// upload instant makes the model `.granted` (never "Declined" once uploaded); nil changes
    /// nothing (absence of data is not a decline).
    public func adoptArrival(_ lastUpload: Date?) {
        if lastUpload != nil { permission = .granted }
    }

    /// Refreshes the computed tiles' hub values (sleep score); unwired loader = stays nil.
    public func refreshComputed() async {
        guard let loadSleepScore else { return }
        sleepScore = await loadSleepScore()
    }

    /// Health app first (Sharing › Apps lives there; `x-apple-health://` is its URL scheme); when
    /// iOS can't open it, the app's own Settings page. No private `App-prefs:` URLs.
    public static func openHealthSettingsOnDevice() {
        #if canImport(UIKit) && !os(watchOS)
        guard let health = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(health) { opened in
            guard !opened, let settings = URL(string: UIApplication.openSettingsURLString) else { return }
            Task { @MainActor in UIApplication.shared.open(settings) }
        }
        #endif
    }

    /// Externally-driven update (B-13, `AppEnvironment.makeHealthPermissionModel`): a fresh
    /// lookup of the real HealthKit status, run without prompting the user (unlike `connect()`,
    /// which triggers the OS permission sheet). Lets the model start honestly at
    /// `.notDetermined` and correct itself once the async HealthKit lookup returns, instead of
    /// blocking construction on it.
    public func adopt(_ permission: HKPermission) {
        self.permission = permission
    }

    /// True when `capability` is NOT in the Apple Watch T2 set — the tile should render as
    /// gated (`EAGatedTile`) rather than a value or a bare zero.
    public func isGated(_ capability: DataCapability) -> Bool {
        !appleWatchCapabilities.contains(capability)
    }

    /// Pure, testable copy for each permission state — denied is never described as "no data";
    /// it names the exact Settings path (wave card exit criterion). HealthKit never confirms a
    /// read denial (see `JIHealthKit.HKPermission` doc comment) — `.granted` copy says so
    /// explicitly rather than promising an instant checkmark: the proof is data arriving after
    /// the first sync, not a HealthKit-reported "yes".
    public static func statusCopy(for permission: HKPermission) -> String {
        switch permission {
        case .granted:
            "Apple Health connected — Watch data appears after the first sync. If nothing arrives, check Health › Sharing › Apps."
        case .denied:
            "Health read access was declined; open Health › Sharing › Apps."
        case .notDetermined:
            "Connect Apple Health to read Watch sleep, heart rate, HRV, steps, resting and active energy, and the food totals your food app writes there."
        }
    }
}
