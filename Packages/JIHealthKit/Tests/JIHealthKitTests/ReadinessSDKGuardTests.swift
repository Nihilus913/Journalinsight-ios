#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
@testable import JIHealthKit

/// W-B74 R-1 (BACKLOG B-74): the "does HealthKit expose the AWU4 Readiness / Sleep score?"
/// re-check as a test instead of a memory.
///
/// Verdict taken on Xcode 27.0 (27A266a), iPhoneOS27.0.sdk, 2026-10-04: NOT exposed (same as
/// 2026-09-16). Every candidate identifier below is resolved by raw value, exactly like
/// `HKReadKind.hrvRMSSDQuantityType` (never the extern constant, which would strong-link), so an
/// unknown identifier yields `nil` instead of a dyld crash.
///
/// WHEN THIS TEST FAILS, a new SDK/runtime exposes a Readiness/Sleep score type → reopen B-74
/// (capability copy in `Capabilities+HK.swift` + `HealthKitProvider.swift:163`). Do NOT
/// auto-claim a capability or wire it as a gate input (2026-09-16: med-confounded, opaque).
/// HT twin: `scripts/sdk_readiness_check.sh` greps the active iphoneos SDK headers.
@Suite struct ReadinessSDKGuardTests {
    static let quantityCandidates = [
        "HKQuantityTypeIdentifierAppleReadiness",
        "HKQuantityTypeIdentifierReadiness",
        "HKQuantityTypeIdentifierReadinessScore",
        "HKQuantityTypeIdentifierAppleSleepScore",
    ]

    static let categoryCandidates = [
        "HKCategoryTypeIdentifierReadiness",
        "HKCategoryTypeIdentifierSleepScore",
    ]

    @Test(arguments: quantityCandidates)
    func readinessQuantityTypeIsNotExposed(_ raw: String) {
        let type = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: raw))
        #expect(type == nil, "\(raw) now resolves — a new SDK exposes Readiness: reopen B-74")
    }

    @Test(arguments: categoryCandidates)
    func readinessCategoryTypeIsNotExposed(_ raw: String) {
        let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: raw))
        #expect(type == nil, "\(raw) now resolves — a new SDK exposes Readiness: reopen B-74")
    }

    /// Positive control: the raw-value lookup itself works, so the nil results above mean
    /// "unknown identifier", not "lookup broken".
    @Test func rawValueLookupResolvesKnownTypes() {
        #expect(HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")) != nil)
        #expect(HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifierSleepAnalysis")) != nil)
    }
}
#endif
