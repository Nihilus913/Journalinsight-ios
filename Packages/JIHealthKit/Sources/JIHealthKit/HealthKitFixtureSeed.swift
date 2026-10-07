#if DEBUG && canImport(HealthKit)
import Foundation
import HealthKit

/// W-OFFLINE2 OFF2-2 (B-50 slice 2): the DEBUG `-seed-healthkit-fixture` seed. The simulator has
/// no Watch, so a no-hub run has nothing on device to show; this writes a fixed, named data set
/// into the sim's HealthKit: 35 nights of sleep (in bed + core/deep/rem/core), HRV SDNN + RMSSD
/// and resting HR per night, 14 days of steps, and 5 workouts (2 runs with route-less distance,
/// 1 strength, 2 walks). Every object carries `JIDebugSeed` (so `HKOwnWrites` reads it back like
/// another app's) and a `ji-fixture:` sync id (never the backloader's `workout:`), and a second
/// run skips every id already in Health. Nothing is in the future of `now`. Never in Release.
public enum HealthKitFixtureSeed {
    public static let launchFlag = "-seed-healthkit-fixture"
    public static let syncPrefix = "ji-fixture:"
    public static let nights = 35
    public static let stepDays = 14

    /// The values the E2E names: today's steps and last night's asleep minutes (7 h 00 m).
    public static let todaySteps = 6543.0
    public static let lastNightAsleepMinutes = 420.0
    /// Last night's HRV SDNN / RMSSD (ms) and resting HR (bpm).
    public static func sdnn(night i: Int) -> Double { 48 + Double((i * 3) % 9) - 4 }
    public static func rmssd(night i: Int) -> Double { 40 + Double((i * 5) % 11) - 5 }
    public static func rhr(night i: Int) -> Double { 52 + Double(i % 5) - 2 }
    static func steps(day i: Int) -> Double { i == 0 ? todaySteps : 8000 + Double((i * 733) % 4000) }

    public struct Report: Equatable, Sendable {
        public let written: Int
        public let skipped: Int
    }

    public static func isRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(launchFlag)
    }

    public static var shareTypes: Set<HKSampleType> {
        let kinds: [HKReadKind] = [.sleepAnalysis, .hrvSDNN, .hrvRMSSD, .restingHeartRate, .stepCount, .workouts]
        return Set(kinds.compactMap(\.sampleType))
    }

    /// Every object the seed writes for `now` (pure — the tests' sample counts).
    public static func objects(now: Date, calendar: Calendar) -> [HKObject] {
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func meta(_ id: String) -> [String: Any] {
            [AppleWorkoutFilter.debugSeedMetadataKey: true, HKMetadataKeySyncIdentifier: "\(syncPrefix)\(id)", HKMetadataKeySyncVersion: 1]
        }
        func dayKey(_ i: Int) -> String {
            let d = calendar.dateComponents([.year, .month, .day], from: at(i, 12))
            return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        }
        var out: [HKObject] = []

        // Sleep: the night ending on day i (23:00 the evening before → 06:30). Last night asleep =
        // 2h45 core + 1h deep + 1h rem + 2h15 core = 7h00; older nights shorten the last core block.
        if let sleepType = HKReadKind.sleepAnalysis.sampleType as? HKCategoryType {
            for i in 0..<nights {
                let key = dayKey(i)
                let trim = (i % 4) * 10
                let blocks: [(HKCategoryValueSleepAnalysis, Date, Date, String)] = [
                    (.inBed, at(i + 1, 23), at(i, 6, 30), "inbed"),
                    (.asleepCore, at(i + 1, 23, 15), at(i, 2), "core1"),
                    (.asleepDeep, at(i, 2), at(i, 3), "deep"),
                    (.asleepREM, at(i, 3), at(i, 4), "rem"),
                    (.asleepCore, at(i, 4), at(i, 6, 15).addingTimeInterval(-Double(trim) * 60), "core2"),
                ]
                for (value, start, end, tag) in blocks {
                    out.append(HKCategorySample(type: sleepType, value: value.rawValue, start: start, end: end,
                                                metadata: meta("sleep:\(key):\(tag)")))
                }
            }
        }

        // HRV (03:00, inside the night) and resting HR (06:00) per night.
        let ms = HKUnit.secondUnit(with: .milli), bpm = HKUnit.count().unitDivided(by: .minute())
        for i in 0..<nights {
            let key = dayKey(i)
            if let t = HKReadKind.hrvSDNN.sampleType as? HKQuantityType {
                out.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: ms, doubleValue: sdnn(night: i)),
                                            start: at(i, 3), end: at(i, 3), metadata: meta("sdnn:\(key)")))
            }
            if let t = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType {
                out.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: ms, doubleValue: rmssd(night: i)),
                                            start: at(i, 3, 5), end: at(i, 3, 5), metadata: meta("rmssd:\(key)")))
            }
            if let t = HKReadKind.restingHeartRate.sampleType as? HKQuantityType {
                out.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: bpm, doubleValue: rhr(night: i)),
                                            start: at(i, 6), end: at(i, 6), metadata: meta("rhr:\(key)")))
            }
        }

        // Steps: one block per day, 07:00 → 20:00 (today: 07:00 → min(now, 20:00)).
        if let t = HKReadKind.stepCount.sampleType as? HKQuantityType {
            for i in 0..<stepDays {
                let start = at(i, 7)
                let end = i == 0 ? min(at(i, 20), max(now, start.addingTimeInterval(60))) : at(i, 20)
                out.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .count(), doubleValue: steps(day: i)),
                                            start: start, end: end, metadata: meta("steps:\(dayKey(i))")))
            }
        }

        // Workouts: 2 runs (distance, no route), 1 strength, 2 walks.
        let plan: [(HKWorkoutActivityType, Int, Int, Int, Double?, Double, String)] = [
            (.running, 1, 7, 45, 8200, 520, "run"),
            (.traditionalStrengthTraining, 3, 18, 50, nil, 280, "strength"),
            (.walking, 4, 12, 30, 2400, 120, "walk"),
            (.running, 6, 7, 60, 10500, 690, "run"),
            (.walking, 8, 17, 40, 3100, 150, "walk"),
        ]
        for (type, day, hour, minutes, meters, kcal, tag) in plan {
            let start = at(day, hour)
            let end = start.addingTimeInterval(Double(minutes) * 60)
            out.append(HKWorkout(activityType: type, start: start, end: end, workoutEvents: nil,
                                 totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                 totalDistance: meters.map { HKQuantity(unit: .meter(), doubleValue: $0) },
                                 metadata: meta("workout-\(tag):\(dayKey(day))")))
        }
        return out.filter { ($0 as? HKSample).map { $0.endDate <= now } ?? true }
    }

    /// Writes what is not in Health yet (by sync id, per type); a second run writes nothing.
    @discardableResult
    public static func run(store: some HealthStoreWriting, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async throws -> Report {
        guard store.isHealthDataAvailable else { return Report(written: 0, skipped: 0) }
        try await store.requestAuthorization(toShare: shareTypes)
        let objects = objects(now: now, calendar: calendar).compactMap { $0 as? HKSample }
        let start = calendar.date(byAdding: .day, value: -(nights + 2), to: now)!
        var toWrite: [HKObject] = []
        var skipped = 0
        for type in Set(objects.map(\.sampleType)) {
            let present = try await store.existingSyncVersions(sampleType: type, start: start, end: now)
            for s in objects where s.sampleType == type {
                let id = s.metadata?[HKMetadataKeySyncIdentifier] as? String ?? ""
                if present[id] != nil { skipped += 1 } else { toWrite.append(s) }
            }
        }
        if !toWrite.isEmpty { try await store.save(toWrite) }
        return Report(written: toWrite.count, skipped: skipped)
    }
}
#endif
