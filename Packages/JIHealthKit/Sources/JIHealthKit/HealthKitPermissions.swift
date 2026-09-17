#if canImport(HealthKit)
import Foundation
import HealthKit

/// Read-authorization state for one `HKReadKind`.
///
/// HealthKit deliberately never confirms a **read** decline — `HKHealthStore
/// .authorizationStatus(for:)` only ever reports the SHARE-side status for a type, which stays
/// `.notDetermined` for a read-only request no matter what the user chose (B-13 root cause: the
/// previous implementation misread that perpetual `.notDetermined` as "declined" the moment a
/// request had been sent, so every grant rendered as `.denied` forever). `HKPermission.granted`
/// is instead PROVEN by `HKAuthorizationRequestStatus.unnecessary` (HealthKit already knows the
/// request would be a no-op, which only happens once the user has answered), and `.denied` is
/// reserved for the one case HealthKit does confirm directly: `.sharingDenied` on the SHARE side.
public enum HKPermission: Sendable, Equatable, Hashable {
    case granted
    case denied
    case notDetermined
}

/// Seam over `HKHealthStore`'s authorization surface so `HealthKitPermissions` (and JIFeatures'
/// `HealthPermissionViewModel`) can be tested without a real store.
public protocol HealthKitAuthorizing: Sendable {
    func requestReadAuthorization(for types: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    /// Mirrors `HKHealthStore.getRequestStatusForAuthorization(toShare:read:)` for a read-only
    /// request. `.shouldRequest` means HealthKit would still show a sheet (never asked, or asked
    /// and the sheet was dismissed without a definitive answer it will report); `.unnecessary`
    /// means the user has already answered — the only way `status(for:)` infers `.granted`.
    func requestStatus(for types: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus
}

extension HKHealthStore: HealthKitAuthorizing {
    public func requestReadAuthorization(for types: Set<HKObjectType>) async throws {
        try await requestAuthorization(toShare: [], read: types)
    }

    public func requestStatus(for types: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        try await statusForAuthorizationRequest(toShare: [], read: types)
    }
}

/// Wraps `HealthKitAuthorizing` with the `HKReadKind` vocabulary and the granted/denied/
/// notDetermined resolution described on `HKPermission`.
public final class HealthKitPermissions: Sendable {
    private let authorizer: any HealthKitAuthorizing

    public init(authorizer: any HealthKitAuthorizing) {
        self.authorizer = authorizer
    }

    /// Requests read access for `kinds` (default: every kind available on this OS). HealthKit's
    /// read-request call never reports per-type outcome — only that the sheet was shown and
    /// dismissed — so this does not return a per-kind result; call `status(for:)` afterward.
    public func requestAuthorization(for kinds: [HKReadKind] = HKReadKind.availableCases) async throws {
        try await authorizer.requestReadAuthorization(for: Set(kinds.compactMap { $0.sampleType as HKObjectType? }))
    }

    /// See the type-level doc comment on `HKPermission`. A kind unavailable on this OS
    /// (pre-iOS-27 `.hrvRMSSD`) is always `.notDetermined`. `requestStatus` throwing (or an
    /// unrecognized case) is treated as `.notDetermined`, never `.denied` — B-13's rule is that
    /// there is NO path from an inconclusive read to `.denied`.
    public func status(for kind: HKReadKind) async -> HKPermission {
        guard let type = kind.sampleType else { return .notDetermined }
        // `.sharingDenied` is the one status HealthKit confirms directly; kept for completeness
        // even though this app only ever requests reads (never share) for these types.
        if authorizer.authorizationStatus(for: type) == .sharingDenied { return .denied }
        guard let requestStatus = try? await authorizer.requestStatus(for: [type]) else { return .notDetermined }
        switch requestStatus {
        case .unnecessary: return .granted
        case .shouldRequest, .unknown: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
#endif
