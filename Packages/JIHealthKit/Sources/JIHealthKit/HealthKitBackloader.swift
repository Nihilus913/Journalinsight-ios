#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore
import JIHub

/// `BackloadRunning` (JICore, frozen) implementation: fetches month chunks from the hub via
/// `BackloadClient`, maps them through `BackloadMapper`, and writes new samples through a
/// `HealthStoreWriting` (real `HKHealthStore` in the app, a fake in tests). Idempotent — every
/// write carries `HKMetadataKeySyncIdentifier`, and each month's existing ids are queried before
/// saving so a re-run writes 0 new samples. Cursor (last fully-written day) persists in the
/// App-Group `UserDefaults` suite (`group.toby913.JournalInsight`, same suite as `SnapshotStore`)
/// under key `hk.backload.cursor`, so a killed/resumed run picks up where it left off.
public final class HealthKitBackloader: BackloadRunning, Sendable {
    private let hub: BackloadClient
    private let store: any HealthStoreWriting
    // UserDefaults is thread-safe by documented contract but predates Sendable annotation on
    // this SDK — same reasoning as `JISnapshot.SnapshotStore`.
    private nonisolated(unsafe) let cursorDefaults: UserDefaults?
    private static let cursorKey = "hk.backload.cursor"
    public static let appGroupSuite = "group.toby913.JournalInsight"

    public init(hub: BackloadClient, store: any HealthStoreWriting = RealHealthStore(), appGroupSuite: String = HealthKitBackloader.appGroupSuite) {
        self.hub = hub
        self.store = store
        self.cursorDefaults = UserDefaults(suiteName: appGroupSuite)
    }

    /// Test seam: inject a `UserDefaults` double directly instead of routing through
    /// `UserDefaults(suiteName:)` (see `SnapshotStore`'s own note on why that initializer can't
    /// be trusted to return `nil` for a bogus suite name across toolchains).
    init(hub: BackloadClient, store: any HealthStoreWriting, defaults: UserDefaults?) {
        self.hub = hub
        self.store = store
        self.cursorDefaults = defaults
    }

    public func authorize() async throws {
        guard store.isHealthDataAvailable else { throw BackloadError.healthDataUnavailable }
        do {
            try await store.requestAuthorization(toShare: Self.allSampleTypes)
        } catch {
            throw BackloadError.authorizationDenied
        }
    }

    public func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
        let chunks = BackloadMonthChunker.chunks(for: range, resumeFrom: readCursor())
        var written = 0, skipped = 0
        var failed: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let dto: BackloadResponseDTO
            do {
                dto = try await hub.fetch(from: chunk.from, to: chunk.to)
            } catch {
                throw BackloadError.hub("\(error)")
            }

            let entries = BackloadMapper.map(dto).flatMap(Self.objectEntries(for:))
            let byType = Dictionary(grouping: entries, by: { ObjectIdentifier($0.type) })
            var existingByType: [ObjectIdentifier: Set<String>] = [:]
            let chunkEnd = chunk.to.addingTimeInterval(86_399) // include the last day fully
            for (key, group) in byType {
                guard let sampleType = group.first?.type else { continue }
                existingByType[key] = (try? await store.existingSyncIds(sampleType: sampleType, start: chunk.from, end: chunkEnd)) ?? []
            }

            var toSave: [HKObject] = []
            for entry in entries {
                if existingByType[ObjectIdentifier(entry.type)]?.contains(entry.syncId) == true {
                    skipped += 1
                } else {
                    toSave.append(entry.object)
                }
            }

            if !toSave.isEmpty {
                do {
                    try await store.save(toSave)
                    written += toSave.count
                } catch {
                    failed.append(contentsOf: toSave.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
                }
            }

            writeCursor(chunk.to)
            progress(BackloadProgress(monthIndex: index + 1, monthCount: chunks.count, written: written, skipped: skipped))
        }

        return BackloadSummary(written: written, skipped: skipped, failed: failed)
    }

    // MARK: - Cursor

    private func readCursor() -> Date? {
        guard let s = cursorDefaults?.string(forKey: Self.cursorKey) else { return nil }
        return BackloadDateParsing.dayBounds(s)?.start
    }

    private func writeCursor(_ date: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BackloadDateParsing.zurich
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return }
        cursorDefaults?.set(String(format: "%04d-%02d-%02d", y, m, d), forKey: Self.cursorKey)
    }

    // MARK: - Spec -> HKObject

    struct ObjectEntry {
        let object: HKObject
        let type: HKSampleType
        let syncId: String
    }

    /// Custom metadata key for average heart rate on a workout — HealthKit has no standard
    /// per-workout average-HR metadata key (only per-sample `HKQuantitySample`s tied to a
    /// workout via `HKWorkoutBuilder` associations); stored here instead to keep the writer on
    /// the plain `save(_:)` seam rather than pulling the builder's async collection API into
    /// `HealthStoreWriting`.
    static let averageHeartRateMetadataKey = "HTAverageHeartRateBPM"

    static func objectEntries(for spec: BackloadWriteSpec) -> [ObjectEntry] {
        switch spec {
        case .quantity(let q):
            guard let type = quantityType(q.kind) else { return [] }
            let metadata: [String: Any] = [HKMetadataKeySyncIdentifier: q.syncId, HKMetadataKeySyncVersion: 1]
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: quantityUnit(q.kind), doubleValue: q.value), start: q.start, end: q.end, metadata: metadata)
            return [ObjectEntry(object: sample, type: type, syncId: q.syncId)]

        case .sleep(let s):
            let sleepType = HKCategoryType(.sleepAnalysis)
            let inBedId = "\(s.syncId):inbed"
            let asleepId = "\(s.syncId):asleep"
            let inBed = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: s.inBedStart, end: s.inBedEnd,
                metadata: [HKMetadataKeySyncIdentifier: inBedId, HKMetadataKeySyncVersion: 1])
            let asleep = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: s.asleepStart, end: s.asleepEnd,
                metadata: [HKMetadataKeySyncIdentifier: asleepId, HKMetadataKeySyncVersion: 1])
            return [
                ObjectEntry(object: inBed, type: sleepType, syncId: inBedId),
                ObjectEntry(object: asleep, type: sleepType, syncId: asleepId),
            ]

        case .workout(let w):
            let type = HKWorkoutType.workoutType()
            var metadata: [String: Any] = [HKMetadataKeySyncIdentifier: w.syncId, HKMetadataKeySyncVersion: 1, HKMetadataKeyWorkoutBrandName: w.name]
            if let avgHr = w.avgHr { metadata[averageHeartRateMetadataKey] = avgHr }
            let energy = w.kcal.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) }
            let distance = w.distanceM.map { HKQuantity(unit: .meter(), doubleValue: $0) }
            let workout = HKWorkout(
                activityType: activityType(w.kind), start: w.start, end: w.end,
                workoutEvents: nil, totalEnergyBurned: energy, totalDistance: distance, metadata: metadata)
            return [ObjectEntry(object: workout, type: type, syncId: w.syncId)]
        }
    }

    static func quantityType(_ kind: BackloadQuantityKind) -> HKQuantityType? {
        switch kind {
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .stepCount: return HKQuantityType(.stepCount)
        case .activeEnergyBurned: return HKQuantityType(.activeEnergyBurned)
        case .basalEnergyBurned: return HKQuantityType(.basalEnergyBurned)
        case .vo2Max: return HKQuantityType(.vo2Max)
        }
    }

    static func quantityUnit(_ kind: BackloadQuantityKind) -> HKUnit {
        switch kind {
        case .restingHeartRate: return HKUnit(from: "count/min")
        case .stepCount: return .count()
        case .activeEnergyBurned, .basalEnergyBurned: return .kilocalorie()
        case .vo2Max: return HKUnit(from: "ml/(kg*min)")
        }
    }

    static func activityType(_ kind: BackloadWorkoutKind) -> HKWorkoutActivityType {
        switch kind {
        case .strength: return .traditionalStrengthTraining
        case .running: return .running
        case .cycling: return .cycling
        case .walking: return .walking
        case .hiking: return .hiking
        case .swimming: return .swimming
        case .other: return .other
        }
    }

    static var allSampleTypes: Set<HKSampleType> {
        [
            HKQuantityType(.restingHeartRate), HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.vo2Max), HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType(),
        ]
    }
}
#endif
