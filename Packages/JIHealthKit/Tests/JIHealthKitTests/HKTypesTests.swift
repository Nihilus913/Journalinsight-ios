#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
import JICore
@testable import JIHealthKit

@Suite struct HKTypesTests {
    @Test func readSetCoversTheCardList() {
        let expected: Set<HKReadKind> = [
            .stepCount, .activeEnergy, .exerciseTime, .restingHeartRate, .hrvSDNN, .hrvRMSSD,
            .sleepAnalysis, .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .workouts,
            .basalEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbs, .dietaryFat,
        ]
        #expect(Set(HKReadKind.allCases) == expected)
    }

    /// B-57 W2 (B-73): resting energy + the food-app day totals are read as quantity types, so
    /// `HKDailyTotalsReader` can sum them with `HKStatisticsCollectionQuery .cumulativeSum`.
    @Test func b73NutritionAndBasalKindsAreQuantityTypes() {
        for kind in [HKReadKind.basalEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbs, .dietaryFat] {
            #expect(kind.sampleType is HKQuantityType)
        }
    }

    /// B-73: the five new kinds join the authorization request (existing installs see them as
    /// not determined until they re-connect — Review Focus 2).
    @Test func b73KindsAreInTheReadRequest() {
        for kind in [HKReadKind.basalEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbs, .dietaryFat] {
            #expect(HKReadKind.allReadTypes.contains(kind.sampleType!))
        }
    }

    @Test func everyKindExceptRMSSDAlwaysResolves() {
        for kind in HKReadKind.allCases where kind != .hrvRMSSD {
            #expect(kind.sampleType != nil, "\(kind) should always resolve to a sample type")
        }
    }

    @Test func hrvRMSSDAvailabilityMatchesSampleTypeNilness() {
        // On this OS, the two must agree: the flag says the type exists iff sampleType resolves.
        #expect((HKReadKind.hrvRMSSD.sampleType != nil) == HKReadKind.hrvRMSSDTypeAvailable)
    }

    @Test func availableCasesDropsOnlyPossiblyRMSSD() {
        let missing = Set(HKReadKind.allCases).subtracting(HKReadKind.availableCases)
        #expect(missing.isEmpty || missing == [.hrvRMSSD])
    }

    @Test func allReadTypesNonEmptyAndSizedToAvailableCases() {
        #expect(HKReadKind.allReadTypes.count == HKReadKind.availableCases.count)
    }

    @Test func workoutsResolveToTheWorkoutType() {
        #expect(HKReadKind.workouts.sampleType == HKWorkoutType.workoutType())
    }

    /// Enforces the W2d L1 exit criterion: `HKQuantityTypeIdentifier`/`HKCategoryTypeIdentifier`
    /// are named only in `HKTypes.swift` and the write-path `Backload*.swift`/
    /// `HealthKitBackloader.swift` files (frozen, W2h/W2i) — everywhere else in
    /// `Sources/JIHealthKit` must work off `HKReadKind` instead of a raw HK identifier.
    @Test func identifierIsolationSourceGrep() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JIHealthKitTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources/JIHealthKit")
        guard let enumerator = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            Issue.record("could not enumerate \(sourcesDir.path)")
            return
        }
        let allowedFiles: Set<String> = ["HKTypes.swift", "HealthKitBackloader.swift"]
        var offenders: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let name = url.lastPathComponent
            guard !allowedFiles.contains(name), !name.hasPrefix("Backload") else { continue }
            let contents = try String(contentsOf: url, encoding: .utf8)
            if contents.contains("HKQuantityTypeIdentifier") || contents.contains("HKCategoryTypeIdentifier") {
                offenders.append(name)
            }
        }
        #expect(offenders.isEmpty, "HK identifiers found outside HKTypes.swift/Backload*.swift: \(offenders)")
    }
}
#endif
