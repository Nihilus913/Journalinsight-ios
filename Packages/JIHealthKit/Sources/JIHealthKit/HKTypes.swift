#if canImport(HealthKit)
import Foundation
import HealthKit

/// The HealthKit **read** set (W2d L1). This is the ONLY file in `JIHealthKit` allowed to name
/// `HKQuantityTypeIdentifier` / `HKCategoryTypeIdentifier` directly — the write path
/// (`Backload*.swift`, `HealthKitBackloader.swift`, frozen, W2h/W2i) is the other place HK
/// identifiers may appear; `HKTypesTests.identifierIsolationSourceGrep` enforces this so every
/// other file in `Sources/JIHealthKit` stays HK-identifier-free and works off `HKReadKind`
/// instead. Read set per the W2d card: steps, active energy, exercise time, resting HR,
/// HRV (SDNN + RMSSD), sleep analysis, body mass/fat/lean/BMI, workouts.
public enum HKReadKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case stepCount
    case activeEnergy
    case exerciseTime
    case restingHeartRate
    case hrvSDNN
    /// iOS 27 `HKQuantityTypeIdentifier.heartRateVariabilityRMSSD` — native RMSSD (see memory
    /// `reference_apple_readiness_app`). The identifier may not exist on an older SDK/OS, so
    /// `sampleType` returns `nil` there instead of naming it unconditionally.
    case hrvRMSSD
    case sleepAnalysis
    case bodyMass
    case bodyFatPercentage
    case leanBodyMass
    case bodyMassIndex
    case workouts

    /// `nil` only for `.hrvRMSSD` when the iOS 27 RMSSD type isn't available — every other kind
    /// always resolves to a concrete `HKSampleType`.
    public var sampleType: HKSampleType? {
        switch self {
        case .stepCount: return HKQuantityType(HKQuantityTypeIdentifier.stepCount)
        case .activeEnergy: return HKQuantityType(HKQuantityTypeIdentifier.activeEnergyBurned)
        case .exerciseTime: return HKQuantityType(HKQuantityTypeIdentifier.appleExerciseTime)
        case .restingHeartRate: return HKQuantityType(HKQuantityTypeIdentifier.restingHeartRate)
        case .hrvSDNN: return HKQuantityType(HKQuantityTypeIdentifier.heartRateVariabilitySDNN)
        case .hrvRMSSD:
            guard Self.hrvRMSSDTypeAvailable else { return nil }
            if #available(iOS 27, watchOS 27, macOS 27, *) {
                return HKQuantityType(HKQuantityTypeIdentifier.heartRateVariabilityRMSSD)
            }
            return nil
        case .sleepAnalysis: return HKCategoryType(HKCategoryTypeIdentifier.sleepAnalysis)
        case .bodyMass: return HKQuantityType(HKQuantityTypeIdentifier.bodyMass)
        case .bodyFatPercentage: return HKQuantityType(HKQuantityTypeIdentifier.bodyFatPercentage)
        case .leanBodyMass: return HKQuantityType(HKQuantityTypeIdentifier.leanBodyMass)
        case .bodyMassIndex: return HKQuantityType(HKQuantityTypeIdentifier.bodyMassIndex)
        case .workouts: return HKWorkoutType.workoutType()
        }
    }

    /// True when the running OS exposes the iOS 27 native-RMSSD HK type. Kept as its own flag
    /// (rather than inlining the `#available` check at every call site) because `Capabilities+HK`
    /// and the permission UI (L3) both need it without importing HealthKit availability logic
    /// themselves.
    public static var hrvRMSSDTypeAvailable: Bool {
        if #available(iOS 27, watchOS 27, macOS 27, *) { return true }
        return false
    }

    /// `allCases` filtered to kinds whose `sampleType` resolves on this OS — i.e. everything
    /// except `.hrvRMSSD` pre-iOS-27.
    public static var availableCases: [HKReadKind] {
        allCases.filter { $0.sampleType != nil }
    }

    /// The read-authorization request set: `availableCases`' sample types, as `HKObjectType`
    /// (workouts included — `HKWorkoutType` is an `HKObjectType`, not an `HKSampleType` read
    /// request is still valid against it).
    public static var allReadTypes: Set<HKObjectType> {
        Set(availableCases.compactMap { $0.sampleType as HKObjectType? })
    }
}
#endif
