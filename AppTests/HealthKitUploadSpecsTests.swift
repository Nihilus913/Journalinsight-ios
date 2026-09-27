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

    /// W-DATA R4: the night's sleeping wrist temperature goes up in °C under the metric name the
    /// hub's `hae_bridge` maps (`apple_sleeping_wrist_temperature` → wake date → core
    /// `wrist_temp_c`); the Recovery "Wrist temp" tile shows only its deviation from baseline.
    @Test func sleepingWristTemperatureIsUploadedInCelsius() {
        let spec = AppEnvironment.healthKitUploadSpecs.first { $0.sampleType.identifier == HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue }
        #expect(spec?.metricName == "apple_sleeping_wrist_temperature")
        #expect(spec?.units == "degC")
        let sample = HKQuantitySample(type: HKQuantityType(.appleSleepingWristTemperature),
                                      quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: 34.61),
                                      start: Date(timeIntervalSince1970: 1_790_460_000), end: Date(timeIntervalSince1970: 1_790_485_000))
        #expect(spec?.mapSamples([sample]).first?.qty == 34.61)
    }

    @Test func theExistingSetIsKept() {
        for id: HKQuantityTypeIdentifier in [.stepCount, .activeEnergyBurned, .appleExerciseTime, .restingHeartRate,
                                             .heartRateVariabilitySDNN, .bodyMass] {
            #expect(byType[id.rawValue] != nil, "\(id.rawValue)")
        }
        #expect(byType[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] == "sleep_analysis")
    }

    /// B-57 W2 (A3): basal energy is now an `HKReadKind`, so it uploads off the read vocabulary
    /// (same type, same metric name, same version-1 anchor — no re-send, no double upload), and
    /// the food totals JI now reads are never uploaded (the hub gets food from YAZIO; JI reads
    /// dietary kinds for on-phone energy balance only).
    @Test func basalRidesTheReadVocabularyAndFoodIsNeverUploaded() {
        let basal = AppEnvironment.healthKitUploadSpecs.filter { $0.sampleType.identifier == HKQuantityTypeIdentifier.basalEnergyBurned.rawValue }
        #expect(basal.count == 1)
        #expect(basal.first?.metricName == "basal_energy_burned")
        #expect(basal.first?.anchorKey == "hk.upload.anchor.\(HKQuantityTypeIdentifier.basalEnergyBurned.rawValue)")
        for id: HKQuantityTypeIdentifier in [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal] {
            #expect(byType[id.rawValue] == nil, "\(id.rawValue)")
        }
    }

    @Test func noTypeIsUploadedTwiceUnderOneAnchor() {
        let keys = AppEnvironment.healthKitUploadSpecs.map(\.anchorKey)
        #expect(Set(keys).count == keys.count)
    }
}
