#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
@testable import JIHealthKit

final class FakeHealthKitAuthorizing: HealthKitAuthorizing, @unchecked Sendable {
    var statuses: [HKObjectType: HKAuthorizationStatus] = [:]
    var requestError: Error?
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
}

struct StubError: Error {}

@Suite struct HealthKitPermissionsTests {
    private func suiteDefaults() -> UserDefaults {
        let name = "HealthKitPermissionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func notDeterminedBeforeAnyRequest() {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake, defaults: suiteDefaults())
        #expect(permissions.status(for: .stepCount) == .notDetermined)
        #expect(permissions.requestedAtLeastOnce == false)
    }

    @Test func grantedWhenHealthKitReportsSharingAuthorized() {
        let fake = FakeHealthKitAuthorizing()
        fake.statuses[HKReadKind.stepCount.sampleType!] = .sharingAuthorized
        let permissions = HealthKitPermissions(authorizer: fake, defaults: suiteDefaults())
        #expect(permissions.status(for: .stepCount) == .granted)
    }

    /// The core disambiguation: HealthKit still reports `.notDetermined` for a declined READ
    /// type (see `HKPermission` doc comment) — only `requestedAtLeastOnce` tells `.denied` apart
    /// from "never asked".
    @Test func deniedInferredAfterRequestWhenStillNotDetermined() async throws {
        let fake = FakeHealthKitAuthorizing()
        let defaults = suiteDefaults()
        let permissions = HealthKitPermissions(authorizer: fake, defaults: defaults)
        #expect(permissions.status(for: .restingHeartRate) == .notDetermined)
        try await permissions.requestAuthorization()
        // HealthKit's read status is unchanged (still .notDetermined under the hood) but the
        // wrapper now infers a decline instead of "never asked".
        #expect(permissions.requestedAtLeastOnce == true)
        #expect(permissions.status(for: .restingHeartRate) == .denied)
    }

    @Test func grantedStaysGrantedAfterRequestRegardlessOfHeuristic() async throws {
        let fake = FakeHealthKitAuthorizing()
        fake.statuses[HKReadKind.stepCount.sampleType!] = .sharingAuthorized
        let permissions = HealthKitPermissions(authorizer: fake, defaults: suiteDefaults())
        try await permissions.requestAuthorization()
        #expect(permissions.status(for: .stepCount) == .granted)
    }

    @Test func unavailableKindIsAlwaysNotDetermined() async throws {
        let fake = FakeHealthKitAuthorizing()
        let defaults = suiteDefaults()
        let permissions = HealthKitPermissions(authorizer: fake, defaults: defaults)
        guard !HKReadKind.hrvRMSSDTypeAvailable else { return } // only meaningful pre-iOS-27
        try await permissions.requestAuthorization()
        #expect(permissions.status(for: .hrvRMSSD) == .notDetermined)
    }

    @Test func requestAuthorizationPropagatesAuthorizerError() async {
        let fake = FakeHealthKitAuthorizing()
        fake.requestError = StubError()
        let permissions = HealthKitPermissions(authorizer: fake, defaults: suiteDefaults())
        await #expect(throws: StubError.self) {
            try await permissions.requestAuthorization()
        }
        #expect(permissions.requestedAtLeastOnce == false, "a throwing request must not mark requestedAtLeastOnce")
    }

    @Test func requestAuthorizationDefaultsToAvailableCases() async throws {
        let fake = FakeHealthKitAuthorizing()
        let permissions = HealthKitPermissions(authorizer: fake, defaults: suiteDefaults())
        try await permissions.requestAuthorization()
        #expect(fake.requestedTypes.count == HKReadKind.availableCases.count)
    }
}
#endif
