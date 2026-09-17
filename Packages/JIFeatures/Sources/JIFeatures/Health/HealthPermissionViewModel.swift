import Foundation
import Observation
import JICore

/// Three-state HealthKit read-permission model (W2d, P-healthkit-permission-ui). Mirrors the
/// shape JIHealthKit's `HKTypes.HKPermission` (L1, parallel lane) is expected to define —
/// JIFeatures never imports JIHealthKit (see `HealthBackloadSection`, and JIFeatures'
/// `Package.swift`, which lists no such dependency), so this is a local value type built
/// against the NAME the wave card gives. If L1 lands a distinct representation, the integrator
/// reconciles the two at merge (wave card: "code against the names the card gives").
///
/// HealthKit can't distinguish "denied" from "never asked" for READ access (Apple's privacy
/// design deliberately hides this) — `notDetermined` covers both, and the UI must never collapse
/// that into "no data" (CLAUDE.md rule 5: never render a zero / false-confident empty state for
/// missing data).
public enum HKPermission: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Drives the "Connect Apple Health" permission flow and which T2 (Apple Watch) tiles are gated
/// (W2d, L3). Built against `HKPermission` above and the plain `DataCapability` bitmap (JICore,
/// already a JIFeatures dependency) — no HealthKit import, no JIHealthKit dependency.
@Observable @MainActor
public final class HealthPermissionViewModel {
    public private(set) var permission: HKPermission

    /// What Apple Watch (HealthKit) can supply on this device/OS — the T2 set (wave card: SDNN
    /// yes; RMSSD only when the iOS 27 type exists; never bodyBattery/trainingReadiness/
    /// garminSleepScore). `AppEnvironment` injects L1's real `appleWatchCapabilities`; this
    /// default (SDNN only) stands in for previews and any test that doesn't override it.
    public let appleWatchCapabilities: DataCapability

    private let requestPermission: () async -> HKPermission

    public init(
        permission: HKPermission = .notDetermined,
        appleWatchCapabilities: DataCapability = [.hrvSDNN],
        requestPermission: @escaping () async -> HKPermission
    ) {
        self.permission = permission
        self.appleWatchCapabilities = appleWatchCapabilities
        self.requestPermission = requestPermission
    }

    /// "Connect Apple Health" button action — calls the injected permission request and adopts
    /// whatever three-state result comes back (never assumes success).
    public func connect() async {
        permission = await requestPermission()
    }

    /// True when `capability` is NOT in the Apple Watch T2 set — the tile should render as
    /// gated (`EAGatedTile`) rather than a value or a bare zero.
    public func isGated(_ capability: DataCapability) -> Bool {
        !appleWatchCapabilities.contains(capability)
    }

    /// Pure, testable copy for each permission state — denied is never described as "no data";
    /// it names the exact Settings path (wave card exit criterion).
    public static func statusCopy(for permission: HKPermission) -> String {
        switch permission {
        case .granted:
            "Apple Health connected."
        case .denied:
            "Health read access was declined; open Health › Sharing › Apps."
        case .notDetermined:
            "Connect Apple Health to read Watch sleep, heart rate, HRV and steps."
        }
    }
}
