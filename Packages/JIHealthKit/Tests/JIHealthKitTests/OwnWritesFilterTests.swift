#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
@testable import JIHealthKit

/// W-FIX10 DH-3 (verdict 08 §1.1, audit 03-F13): the phone never re-reads — so never re-uploads,
/// and the on-device provider never reports — its own HealthKit writes (the Garmin backload
/// writes RMSSD / RHR / sleep as this app). Every anchored read (`RealHealthStoreReader
/// .anchoredSamples`, which `HealthKitUploader` and `HealthKitProvider.samples(for:)` both go
/// through) carries NOT-this-app, except this app's `JIDebugSeed` samples (the sim seeder).
/// Workouts keep their own filter (`AppleWorkoutFilter.isHubBackload`): the watch app records
/// real workouts as this app.
@Suite struct OwnWritesFilterTests {
    /// Stand-in for `HKQuery.predicateForObjects(from: HKSource.default())` (a package test host
    /// has no bundle id, so the default source cannot be built here).
    private let own = NSPredicate(format: "sourceMarker == 'JournalInsight'")
    private let since = Date(timeIntervalSince1970: 1_790_000_000)

    private func notOurs(_ p: NSPredicate?) -> Bool {
        guard let c = p as? NSCompoundPredicate else { return false }
        if c.compoundPredicateType == .or {
            let subs = c.subpredicates.compactMap { $0 as? NSPredicate }
            let negatesOwn = subs.contains { ($0 as? NSCompoundPredicate)?.compoundPredicateType == .not
                && (($0 as? NSCompoundPredicate)?.subpredicates.first as? NSPredicate) == own }
            let keepsSeed = subs.contains { $0.predicateFormat.contains(AppleWorkoutFilter.debugSeedMetadataKey) }
            return negatesOwn && keepsSeed
        }
        return c.subpredicates.contains { notOurs($0 as? NSPredicate) }
    }

    @Test func quantityReadsExcludeThisAppsOwnWrites() {
        for kind in [HKReadKind.hrvRMSSD, .restingHeartRate, .hrvSDNN, .sleepAnalysis, .stepCount, .bodyMass] {
            guard let type = kind.sampleType else { continue }
            #expect(notOurs(HKOwnWrites.anchoredPredicate(sampleType: type, since: nil, ownSource: own)), "\(kind)")
            #expect(notOurs(HKOwnWrites.anchoredPredicate(sampleType: type, since: since, ownSource: own)), "\(kind) with since")
        }
    }

    @Test func theSinceBoundIsKept() {
        let type = HKReadKind.restingHeartRate.sampleType!
        let p = HKOwnWrites.anchoredPredicate(sampleType: type, since: since, ownSource: own) as? NSCompoundPredicate
        #expect(p?.compoundPredicateType == .and)
        #expect(p?.subpredicates.count == 2)
    }

    @Test func workoutsKeepTheirOwnFilter() {
        let w = HKWorkoutType.workoutType()
        #expect(HKOwnWrites.anchoredPredicate(sampleType: w, since: nil, ownSource: own) == nil)
        #expect(!notOurs(HKOwnWrites.anchoredPredicate(sampleType: w, since: since, ownSource: own)))
        #expect(HKOwnWrites.anchoredPredicate(sampleType: w, since: since, ownSource: own) != nil)
    }
}
#endif
