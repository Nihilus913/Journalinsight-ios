import Foundation
import HealthKit
import Testing
@testable import JournalInsight

/// W-FIX2 L5 (FM-10): every HealthKit type the hub has a column for is in the upload list —
/// body fat, lean mass and BMI (read-authorized but never uploaded since the HAE era ended
/// 07-23), plus respiratory rate, SpO2, basal energy and VO2max. The uploader requests read
/// access for exactly its specs, so adding a type here is also what asks for it.
@MainActor
struct HealthKitUploadSpecsTests {
    private var byType: [String: String] {
        Dictionary(AppEnvironment.healthKitUploadSpecs.map { ($0.sampleType.identifier, $0.metricName) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func bodyCompositionIsUploaded() {
        #expect(byType[HKQuantityTypeIdentifier.bodyFatPercentage.rawValue] == "body_fat_percentage")
        #expect(byType[HKQuantityTypeIdentifier.leanBodyMass.rawValue] == "lean_body_mass")
        #expect(byType[HKQuantityTypeIdentifier.bodyMassIndex.rawValue] == "body_mass_index")
    }

    @Test func respirationSpO2BasalAndVO2maxAreUploaded() {
        #expect(byType[HKQuantityTypeIdentifier.respiratoryRate.rawValue] == "respiratory_rate")
        #expect(byType[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] == "blood_oxygen_saturation")
        #expect(byType[HKQuantityTypeIdentifier.basalEnergyBurned.rawValue] == "basal_energy_burned")
        #expect(byType[HKQuantityTypeIdentifier.vo2Max.rawValue] == "vo2_max")
    }

    @Test func theExistingSetIsKept() {
        for id: HKQuantityTypeIdentifier in [.stepCount, .activeEnergyBurned, .appleExerciseTime, .restingHeartRate,
                                             .heartRateVariabilitySDNN, .bodyMass] {
            #expect(byType[id.rawValue] != nil, "\(id.rawValue)")
        }
        #expect(byType[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] == "sleep_analysis")
    }

    @Test func noTypeIsUploadedTwiceUnderOneAnchor() {
        let keys = AppEnvironment.healthKitUploadSpecs.map(\.anchorKey)
        #expect(Set(keys).count == keys.count)
    }
}
