#if canImport(HealthKit)
import Foundation
import HealthKit

/// Read-authorization state for one `HKReadKind`.
///
/// HealthKit deliberately never distinguishes, for a **read** type, "the user was asked and said
/// no" from "the user was never asked" — `HKHealthStore.authorizationStatus(for:)` reports
/// `.notDetermined` for both, by design, so a denial can't leak whether the app would otherwise
/// have seen data. `.denied` below is therefore a HEURISTIC this type infers (via
/// `requestedAtLeastOnce`, §`HealthKitPermissions`), never a value HealthKit hands back directly
/// for a read type — callers must not treat it as more certain than that.
public enum HKPermission: Sendable, Equatable, Hashable {
    case granted
    case denied
    case notDetermined
}

/// Seam over `HKHealthStore`'s authorization surface so `HealthKitPermissions` (and L3's
/// `HealthPermissionViewModel`) can be tested without a real store.
public protocol HealthKitAuthorizing: Sendable {
    func requestReadAuthorization(for types: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
}

extension HKHealthStore: HealthKitAuthorizing {
    public func requestReadAuthorization(for types: Set<HKObjectType>) async throws {
        try await requestAuthorization(toShare: [], read: types)
    }
}

/// Wraps `HealthKitAuthorizing` with the `HKReadKind` vocabulary and the notDetermined/denied
/// disambiguation heuristic described on `HKPermission`.
public final class HealthKitPermissions: Sendable {
    private let authorizer: any HealthKitAuthorizing
    // UserDefaults is thread-safe by documented contract but predates Sendable annotation on
    // this SDK — same reasoning as `HealthKitBackloader.cursorDefaults`.
    private nonisolated(unsafe) let defaults: UserDefaults?
    /// App-Group `UserDefaults` key (same suite as `HealthKitBackloader`'s cursor): set once a
    /// read request has completed without throwing, regardless of what the user chose. This is
    /// what lets `status(for:)` ever report `.denied` instead of `.notDetermined` forever.
    public static let requestedKey = "hk.read.requestedAtLeastOnce"

    public init(authorizer: any HealthKitAuthorizing, appGroupSuite: String = "group.toby913.JournalInsight") {
        self.authorizer = authorizer
        self.defaults = UserDefaults(suiteName: appGroupSuite)
    }

    /// Test seam: inject a `UserDefaults` double directly (mirrors `HealthKitBackloader`'s own
    /// `init(hub:store:defaults:)` seam and its rationale).
    init(authorizer: any HealthKitAuthorizing, defaults: UserDefaults?) {
        self.authorizer = authorizer
        self.defaults = defaults
    }

    public var requestedAtLeastOnce: Bool { defaults?.bool(forKey: Self.requestedKey) ?? false }

    /// Requests read access for `kinds` (default: every kind available on this OS) and marks
    /// `requestedAtLeastOnce`. HealthKit's read-request call never reports per-type outcome —
    /// only that the sheet was shown and dismissed — so this does not return a per-kind result;
    /// call `status(for:)` afterward.
    public func requestAuthorization(for kinds: [HKReadKind] = HKReadKind.availableCases) async throws {
        try await authorizer.requestReadAuthorization(for: Set(kinds.compactMap { $0.sampleType as HKObjectType? }))
        defaults?.set(true, forKey: Self.requestedKey)
    }

    /// See the type-level doc comment on `HKPermission`: a read type's HealthKit status is
    /// `.notDetermined` both before the first request and after a decline. This resolves the
    /// ambiguity with `requestedAtLeastOnce` — still a heuristic, not a HealthKit-confirmed
    /// decline (the OS never confirms one for reads). A kind unavailable on this OS (pre-iOS-27
    /// `.hrvRMSSD`) is always `.notDetermined`.
    public func status(for kind: HKReadKind) -> HKPermission {
        guard let type = kind.sampleType else { return .notDetermined }
        switch authorizer.authorizationStatus(for: type) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied // HealthKit reports this for SHARE types; kept for completeness
        case .notDetermined: return requestedAtLeastOnce ? .denied : .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
#endif
