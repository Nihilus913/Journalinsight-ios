#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
@testable import JIHealthKit

final class FakeHealthKitAuthorizing: HealthKitAuthorizing, @unchecked Sendable {
    var statuses: [HKObjectType: HKAuthorizationStatus] = [:]
    var requestStatuses: [HKObjectType: HKAuthorizationRequestStatus] = [:]
    var requestError: Error?
    var requestStatusError: Error?
    private(set) var requestedTypes: Set<HKObjectType> = []
    private(set) var requestCount = 0

    func requestReadAuthorization(for types: Set<HKObjectType>) async throws {
        requestCount += 1
        requestedTypes = types
        if let requestError { throw requestError }
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        statuses[type] ?? .notDetermined
    }

    func requestStatus(for types: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        if let requestStatusError { throw requestStatusError }
        // Every kind in `types` should carry the same request status in these tests (single-kind
        // calls from `status(for:)`); fall back to `.shouldRequest` (never asked) when unset.
        return types.compactMap { requestStatuses[$0] }.first ?? .shouldRequest
    }
}

struct StubError: Error {}

@Suite struct HealthKitPermissionsTests {
    @Test func notDeterminedBeforeAnyRequest() async {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .stepCount) == .notDetermined)
    }

    @Test func grantedWhenRequestStatusIsUnnecessary() async {
        let fake = FakeHealthKitAuthorizing()
        fake.requestStatuses[HKReadKind.stepCount.sampleType!] = .unnecessary
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .stepCount) == .granted)
    }

    /// The B-13 regression: `authorizationStatus(for:)` reports the SHARE status only, and for a
    /// read-only request that stays `.notDetermined` even after a real grant. The OLD code
    /// treated "asked once, still notDetermined" as `.denied` — the fix must NOT do that; a
    /// still-inconclusive read stays `.notDetermined`, never flips to `.denied`, no matter how
    /// many times `requestAuthorization` has run.
    @Test func stillShouldRequestAfterRequestingStaysNotDeterminedNeverDenied() async throws {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .restingHeartRate) == .notDetermined)
        try await permissions.requestAuthorization()
        // HealthKit's read status is unchanged (still `.shouldRequest` under the hood) — the
        // wrapper must keep reporting `.notDetermined`, not infer a decline.
        #expect(await permissions.status(for: .restingHeartRate) == .notDetermined)
    }

    @Test func grantedStaysGrantedRegardlessOfRequestCount() async throws {
        let fake = FakeHealthKitAuthorizing()
        fake.requestStatuses[HKReadKind.stepCount.sampleType!] = .unnecessary
        let permissions = HealthKitPermissions(authorizer: fake)
        try await permissions.requestAuthorization()
        #expect(await permissions.status(for: .stepCount) == .granted)
    }

    /// `.sharingDenied` is the one status HealthKit confirms directly — kept as the only path to
    /// `.denied`, even when `requestStatus` (queried on the read side) would otherwise say
    /// `.shouldRequest`.
    @Test func sharingDeniedMapsToDeniedEvenWhenRequestStatusSaysShouldRequest() async {
        let fake = FakeHealthKitAuthorizing()
        let type = HKReadKind.stepCount.sampleType!
        fake.statuses[type] = .sharingDenied
        fake.requestStatuses[type] = .shouldRequest
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .stepCount) == .denied)
    }

    @Test func unknownRequestStatusMapsToNotDeterminedNeverDenied() async {
        let fake = FakeHealthKitAuthorizing()
        fake.requestStatuses[HKReadKind.stepCount.sampleType!] = .unknown
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .stepCount) == .notDetermined)
    }

    @Test func requestStatusErrorMapsToNotDeterminedNeverDenied() async {
        let fake = FakeHealthKitAuthorizing()
        fake.requestStatusError = StubError()
        let permissions = HealthKitPermissions(authorizer: fake)
        #expect(await permissions.status(for: .stepCount) == .notDetermined)
    }

    @Test func unavailableKindIsAlwaysNotDetermined() async throws {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake)
        guard !HKReadKind.hrvRMSSDTypeAvailable else { return } // only meaningful pre-iOS-27
        try await permissions.requestAuthorization()
        #expect(await permissions.status(for: .hrvRMSSD) == .notDetermined)
    }

    @Test func requestAuthorizationPropagatesAuthorizerError() async {
        let fake = FakeHealthKitAuthorizing()
        fake.requestError = StubError()
        let permissions = HealthKitPermissions(authorizer: fake)
        await #expect(throws: StubError.self) {
            try await permissions.requestAuthorization()
        }
    }

    @Test func requestAuthorizationDefaultsToAvailableCases() async throws {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake)
        try await permissions.requestAuthorization()
        #expect(fake.requestedTypes.count == HKReadKind.availableCases.count)
    }
}
#endif
