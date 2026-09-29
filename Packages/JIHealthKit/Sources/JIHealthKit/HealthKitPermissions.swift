#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// Read-authorization state for one `HKReadKind`.
///
/// HealthKit deliberately never confirms a **read** decline — `HKHealthStore
/// .authorizationStatus(for:)` only ever reports the SHARE-side status for a type, which stays
/// `.notDetermined` for a read-only request no matter what the user chose (B-13 root cause: the
/// previous implementation misread that perpetual `.notDetermined` as "declined" the moment a
/// request had been sent, so every grant rendered as `.denied` forever). `HKPermission.granted`
/// is instead PROVEN by `HKAuthorizationRequestStatus.unnecessary` (HealthKit already knows the
/// request would be a no-op, which only happens once the user has answered). DEV-12 (W-DATA R2):
/// `.sharingDenied` is NOT a read decline — JI never requests share, so HealthKit reports it for
/// every read type once the sheet is answered, allowed or not ("Declined" on types uploading 200).
/// No read path produces `.denied`; the case stays for the view copy. Data arriving
/// (`HealthKitArrival`) is the only proof of a read grant.
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
        // `authorizer.authorizationStatus(for:)` is deliberately NOT consulted: it is the share
        // status, and `.sharingDenied` there says nothing about reads (DEV-12).
        guard let requestStatus = try? await authorizer.requestStatus(for: [type]) else { return .notDetermined }
        switch requestStatus {
        case .unnecessary: return .granted
        case .shouldRequest, .unknown: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

/// DEV-12 (W-DATA R2): when HealthKit data last ARRIVED at the hub, per sample type — the honest
/// "Connected" signal (iOS never reports a read grant). The uploader records the 2xx instant
/// under `globalKey` (B-65) and, per type, under `key(for:)` (ISO-8601, App-Group suite).
public enum HealthKitArrival {
    /// `PrefKeys.hkLastUploadSuccess` (JICore) — the same record `HealthKitUploader` writes.
    public static let globalKey = PrefKeys.hkLastUploadSuccess

    /// `hk.upload.lastSuccess.<HK type identifier>`.
    public static func key(for sampleType: HKSampleType) -> String {
        "\(globalKey).\(sampleType.identifier)"
    }

    /// The latest per-type arrival among `kinds` (a kind unavailable on this OS is skipped). When
    /// the suite has NO per-type record for any read kind (an install that uploaded before the
    /// per-type writer), falls back to the global instant; once per-type records exist, a kind
    /// without one has not arrived → nil ("No data yet", never "Declined").
    public static func lastUpload(for kinds: [HKReadKind], in defaults: UserDefaults?) -> Date? {
        guard let defaults else { return nil }
        let dates = kinds.compactMap { $0.sampleType }.compactMap { date(defaults.string(forKey: key(for: $0))) }
        if let latest = dates.max() { return latest }
        let anyPerType = HKReadKind.allCases.contains { kind in
            kind.sampleType.map { defaults.string(forKey: key(for: $0)) != nil } ?? false
        }
        return anyPerType ? nil : date(defaults.string(forKey: globalKey))
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: raw) { return d }
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: raw)
    }
}
#endif
