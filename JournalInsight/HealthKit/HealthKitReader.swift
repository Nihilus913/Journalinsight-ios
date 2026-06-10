// JournalInsight/HealthKit/HealthKitReader.swift
import Foundation
import HealthKit

// Snapshot of latest recovery values — passed to TrainingWidgetView
struct RecoverySnapshot {
    var sleepScore: Double?        // 0–100 (Garmin writes to HK as metadata; often nil)
    var sleepDurationSec: Double?
    var deepSleepSec: Double?
    var restingHR: Double?
    var hrv: Double?
    var lastUpdated: Date?
}

actor HealthKitReader {
    private let store: HKHealthStore

    init(store: HKHealthStore = .init()) {
        self.store = store
    }

    func latestRecovery() async -> RecoverySnapshot {
        async let rhr = latestQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"))
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let sleep = latestSleep()

        let rhrVal = await rhr
        let hrvVal = await hrv
        let (sleepDur, sleepDeep) = await sleep

        // sleepScore intentionally nil in SP2 — populated from Garmin metadata in SP4.
        return RecoverySnapshot(
            sleepDurationSec: sleepDur,
            deepSleepSec: sleepDeep,
            restingHR: rhrVal,
            hrv: hrvVal,
            lastUpdated: .now
        )
    }

    static func normaliseSleepScore(_ score: Double) -> Double {
        min(1.0, max(0.0, score / 100.0))
    }

    static func formattedRHR(_ bpm: Double?) -> String {
        guard let v = bpm else { return "—" }
        return "\(Int(v)) bpm"
    }

    private func latestQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let qtype = HKQuantityType(type)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: qtype,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                    end: .now),
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func latestSleep() async -> (duration: Double?, deep: Double?) {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                let total = samples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let deep = samples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: (total > 0 ? total : nil, deep > 0 ? deep : nil))
            }
            store.execute(query)
        }
    }
}
