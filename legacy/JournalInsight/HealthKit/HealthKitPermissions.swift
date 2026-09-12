// JournalInsight/HealthKit/HealthKitPermissions.swift
import HealthKit

enum HealthKitPermissions {

    static let shared = HKHealthStore()

    // All types the app reads — requested together on first Training feature use
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.bodyMass),
        ]
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        return types
    }

    // App writes nothing to HealthKit
    static var writeTypes: Set<HKSampleType> { [] }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
}
