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
    /// App-Group pref (written by JIFeatures' Settings toggle, L4): write Garmin RMSSD readings
    /// under Apple's `heartRateVariabilitySDNN` type. Default OFF — Garmin RMSSD and Apple SDNN
    /// are different metrics, per the v2 contract note.
    static let writeHRVKey = "hk.backload.writeHRV"
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
        // One-time upgrade: an older writer version walks the whole range again and rewrites
        // the kinds that changed shape (v3: workouts). Everything else is skipped by sync id.
        let storedVersion = cursorDefaults?.integer(forKey: Self.writerVersionKey) ?? 0
        if storedVersion < Self.writerVersion { cursorDefaults?.removeObject(forKey: Self.cursorKey) }
        let chunks = BackloadMonthChunker.chunks(for: range, resumeFrom: readCursor())
        var written = 0, skipped = 0
        var failed: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let dto: BackloadResponseDTO
            do {
                // Two passes per chunk (see `BackloadMonthChunker`'s doc comment): the hub
                // defaults an omitted `kinds` to daily-only, so the dense series (stages,
                // heart_rate, respiration, spo2, hrv_readings, step_buckets) must be requested
                // explicitly or they never come back — every array would stay `[]` forever.
                let dailyDTO = try await hub.fetch(from: chunk.from, to: chunk.to, kinds: BackloadMonthChunker.dailyPassKinds)
                let denseDTO = try await hub.fetch(from: chunk.from, to: chunk.to, kinds: BackloadMonthChunker.densePassKinds)
                dto = Self.merge(daily: dailyDTO, dense: denseDTO)
            } catch {
                throw BackloadError.hub("\(error)")
            }

            let allSpecs = BackloadMapper.map(dto)
            let writeHRV = cursorDefaults?.bool(forKey: Self.writeHRVKey) ?? false

            // Deletions (v1 markers superseded by v2 writes) happen before the save pass so a
            // fresh `existingSyncIds` read (below) never sees the object it's about to replace.
            var deletionsByKind: [BackloadDeleteKind: Set<String>] = [:]
            var writableSpecs: [BackloadWriteSpec] = []
            for spec in allSpecs {
                switch spec {
                case .delete(let kind, let syncId):
                    deletionsByKind[kind, default: []].insert(syncId)
                case .quantity(let q) where q.kind == .hrvSDNN && !writeHRV:
                    continue // HRV gated by the App-Group pref; drop silently, no delete either
                default:
                    writableSpecs.append(spec)
                }
            }
            for (kind, syncIds) in deletionsByKind {
                try? await store.deleteObjects(sampleType: Self.sampleType(for: kind), syncIdentifiers: syncIds)
            }

            let entries = writableSpecs.flatMap(Self.objectEntries(for:))
            let byType = Dictionary(grouping: entries, by: { ObjectIdentifier($0.type) })
            var existingByType: [ObjectIdentifier: Set<String>] = [:]
            let chunkEnd = chunk.to.addingTimeInterval(86_399) // include the last day fully
            for (key, group) in byType {
                guard let sampleType = group.first?.type else { continue }
                existingByType[key] = (try? await store.existingSyncIds(sampleType: sampleType, start: chunk.from, end: chunkEnd)) ?? []
            }

            var toSave: [HKObject] = []
            var toAssociate: [(HKWorkout, [HKSample])] = []
            for entry in entries {
                if let workout = entry.object as? HKWorkout {
                    // Workouts are always force-overwritten (Toby 2026-09-17): delete the old
                    // object + its associated samples by sync id, then re-save and re-attach —
                    // never a duplicate, never a stale ring credit.
                    try? await store.deleteObjects(sampleType: entry.type, syncIdentifiers: [entry.syncId])
                    for sample in entry.associated {
                        if let sid = sample.metadata?[HKMetadataKeySyncIdentifier] as? String {
                            try? await store.deleteObjects(sampleType: sample.sampleType, syncIdentifiers: [sid])
                        }
                    }
                    toSave.append(workout)
                    if !entry.associated.isEmpty { toAssociate.append((workout, entry.associated)) }
                } else if existingByType[ObjectIdentifier(entry.type)]?.contains(entry.syncId) == true {
                    skipped += 1
                } else {
                    toSave.append(entry.object)
                    if let workout = entry.object as? HKWorkout, !entry.associated.isEmpty {
                        toAssociate.append((workout, entry.associated))
                    }
                }
            }

            if !toSave.isEmpty {
                do {
                    try await store.save(toSave)
                    written += toSave.count
                    for (workout, samples) in toAssociate {
                        do { try await store.add(samples, to: workout); written += samples.count }
                        catch { failed.append((workout.metadata?[HKMetadataKeySyncIdentifier] as? String ?? "workout") + ":associated") }
                    }
                } catch {
                    failed.append(contentsOf: toSave.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
                }
            }

            writeCursor(chunk.to)
            progress(BackloadProgress(monthIndex: index + 1, monthCount: chunks.count, written: written, skipped: skipped))
        }

        cursorDefaults?.set(Self.writerVersion, forKey: Self.writerVersionKey)
        // The cursor only resumes a killed run; a completed run clears it so the next tap walks the
        // whole range again (workouts force-overwrite, other kinds skip by sync id). The UI shows
        // `lastCompletedKey` instead.
        if let done = cursorDefaults?.string(forKey: Self.cursorKey) { cursorDefaults?.set(done, forKey: Self.lastCompletedKey) }
        cursorDefaults?.removeObject(forKey: Self.cursorKey)
        return BackloadSummary(written: written, skipped: skipped, failed: failed)
    }

    // MARK: - Response merge

    /// Combines one chunk's daily-pass and dense-pass responses into a single DTO before
    /// `BackloadMapper.map` sees it. `sleep` (with stage intervals, when Garmin has them) and
    /// every genuinely-dense series come from `dense`; everything else comes from `daily`. Both
    /// responses cover the same `from`/`to` chunk, so metadata is taken from `daily`.
    ///
    /// This has to be a merge, not two separate `map` calls, because `BackloadMapper`'s
    /// daily_resp/daily_spo2 fallback gating (only write the daily average when no dense sample
    /// exists for that date) reads `dto.respiration`/`dto.spo2` to decide — those arrays are `[]`
    /// on the daily-only response by construction, which would make the gate fire on every date
    /// and double-write, so the dense series has to be present in the same dto being mapped.
    static func merge(daily: BackloadResponseDTO, dense: BackloadResponseDTO) -> BackloadResponseDTO {
        BackloadResponseDTO(
            from: daily.from, to: daily.to, source: daily.source,
            sleep: dense.sleep, rhr: daily.rhr, steps: daily.steps, energy: daily.energy,
            vo2max: daily.vo2max, workouts: daily.workouts,
            heartRate: dense.heartRate, respiration: dense.respiration, spo2: dense.spo2, hrv: dense.hrv,
            stepBuckets: dense.stepBuckets, dailyResp: daily.dailyResp, dailySpo2: daily.dailySpo2
        )
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
        /// Samples to attach to `object` (an `HKWorkout`) after it is saved — see `HealthStoreWriting.add`.
        var associated: [HKSample] = []
    }

    /// Bumped when an already-written kind must be rewritten (HealthKit replaces objects whose
    /// `HKMetadataKeySyncIdentifier` matches and whose `HKMetadataKeySyncVersion` is higher).
    /// v3: workouts gain associated energy/distance samples so Fitness credits the rings.
    static let writerVersion = 3
    static let writerVersionKey = "hk.backload.writerVersion"
    static let workoutSyncVersion = 3
    static let lastCompletedKey = "hk.backload.lastCompletedDay"

    /// Custom metadata key for average heart rate on a workout — HealthKit has no standard
    /// per-workout average-HR metadata key (only per-sample `HKQuantitySample`s tied to a
    /// workout via `HKWorkoutBuilder` associations); stored here instead to keep the writer on
    /// the plain `save(_:)` seam rather than pulling the builder's async collection API into
    /// `HealthStoreWriting`.
    static let averageHeartRateMetadataKey = "HTAverageHeartRateBPM"

    /// v2: every write — new kinds and the v1 ones alike — carries `HKMetadataKeySyncVersion = 2`
    /// per the frozen contract note ("everything keeps ... SyncVersion = 2"). Idempotency itself
    /// only keys off the sync identifier, so this bump doesn't disturb existing v1 objects still
    /// on a device that hasn't re-run since.
    static let syncVersion = 2

    static func objectEntries(for spec: BackloadWriteSpec) -> [ObjectEntry] {
        switch spec {
        case .quantity(let q):
            guard let type = quantityType(q.kind) else { return [] }
            let metadata: [String: Any] = [HKMetadataKeySyncIdentifier: q.syncId, HKMetadataKeySyncVersion: syncVersion]
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: quantityUnit(q.kind), doubleValue: q.value), start: q.start, end: q.end, metadata: metadata)
            return [ObjectEntry(object: sample, type: type, syncId: q.syncId)]

        case .sleep(let s):
            let sleepType = HKCategoryType(.sleepAnalysis)
            let inBedId = "\(s.syncId):inbed"
            let asleepId = "\(s.syncId):asleep"
            let inBed = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: s.inBedStart, end: s.inBedEnd,
                metadata: [HKMetadataKeySyncIdentifier: inBedId, HKMetadataKeySyncVersion: syncVersion])
            let asleep = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: s.asleepStart, end: s.asleepEnd,
                metadata: [HKMetadataKeySyncIdentifier: asleepId, HKMetadataKeySyncVersion: syncVersion])
            return [
                ObjectEntry(object: inBed, type: sleepType, syncId: inBedId),
                ObjectEntry(object: asleep, type: sleepType, syncId: asleepId),
            ]

        case .sleepStaged(let s):
            let sleepType = HKCategoryType(.sleepAnalysis)
            let inBedId = "\(s.baseSyncId):inbed"
            let inBed = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: s.inBedStart, end: s.inBedEnd,
                metadata: [HKMetadataKeySyncIdentifier: inBedId, HKMetadataKeySyncVersion: syncVersion])
            var out = [ObjectEntry(object: inBed, type: sleepType, syncId: inBedId)]
            for stage in s.stages {
                let sample = HKCategorySample(
                    type: sleepType, value: stageCategoryValue(stage.stage),
                    start: stage.start, end: stage.end,
                    metadata: [HKMetadataKeySyncIdentifier: stage.syncId, HKMetadataKeySyncVersion: syncVersion])
                out.append(ObjectEntry(object: sample, type: sleepType, syncId: stage.syncId))
            }
            return out

        case .workout(let w):
            let type = HKWorkoutType.workoutType()
            var metadata: [String: Any] = [HKMetadataKeySyncIdentifier: w.syncId, HKMetadataKeySyncVersion: workoutSyncVersion, HKMetadataKeyWorkoutBrandName: w.name]
            if let avgHr = w.avgHr { metadata[averageHeartRateMetadataKey] = avgHr }
            if w.startEstimated { metadata[startEstimatedMetadataKey] = true }
            let energy = w.kcal.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) }
            let distance = w.distanceM.map { HKQuantity(unit: .meter(), doubleValue: $0) }
            let workout = HKWorkout(
                activityType: activityType(w.kind), start: w.start, end: w.end,
                workoutEvents: nil, totalEnergyBurned: energy, totalDistance: distance, metadata: metadata)
            // Associated samples: this is what Fitness sums into the Move ring (energy) and what
            // the workout detail shows as distance. Sync ids derive from the workout's.
            var associated: [HKSample] = []
            if let energy {
                associated.append(HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned), quantity: energy, start: w.start, end: w.end,
                    metadata: [HKMetadataKeySyncIdentifier: "\(w.syncId):energy", HKMetadataKeySyncVersion: workoutSyncVersion]))
            }
            if let distance, let distanceType = distanceType(w.kind) {
                associated.append(HKQuantitySample(
                    type: distanceType, quantity: distance, start: w.start, end: w.end,
                    metadata: [HKMetadataKeySyncIdentifier: "\(w.syncId):distance", HKMetadataKeySyncVersion: workoutSyncVersion]))
            }
            return [ObjectEntry(object: workout, type: type, syncId: w.syncId, associated: associated)]

        case .delete:
            return [] // handled in `run` before mapping to objects, never saved
        }
    }

    /// Custom metadata key noting a workout's `start` is the hub's 12:00 fallback rather than a
    /// real Garmin activity start (`start_time_utc` missing) — surfaced for debugging only.
    static let startEstimatedMetadataKey = "HTStartEstimated"

    static func quantityType(_ kind: BackloadQuantityKind) -> HKQuantityType? {
        switch kind {
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .stepCount: return HKQuantityType(.stepCount)
        case .activeEnergyBurned: return HKQuantityType(.activeEnergyBurned)
        case .basalEnergyBurned: return HKQuantityType(.basalEnergyBurned)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .heartRate: return HKQuantityType(.heartRate)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: return HKQuantityType(.oxygenSaturation)
        case .hrvSDNN: return HKQuantityType(.heartRateVariabilitySDNN)
        }
    }

    static func quantityUnit(_ kind: BackloadQuantityKind) -> HKUnit {
        switch kind {
        case .restingHeartRate, .heartRate, .respiratoryRate: return HKUnit(from: "count/min")
        case .stepCount: return .count()
        case .activeEnergyBurned, .basalEnergyBurned: return .kilocalorie()
        case .vo2Max: return HKUnit(from: "ml/(kg*min)")
        case .oxygenSaturation: return .percent() // written as a 0–1 fraction, per HK convention
        case .hrvSDNN: return HKUnit.secondUnit(with: .milli)
        }
    }

    static func stageCategoryValue(_ stage: BackloadSleepStageKind) -> Int {
        switch stage {
        case .deep: return HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        case .light: return HKCategoryValueSleepAnalysis.asleepCore.rawValue
        case .rem: return HKCategoryValueSleepAnalysis.asleepREM.rawValue
        case .awake: return HKCategoryValueSleepAnalysis.awake.rawValue
        }
    }

    static func sampleType(for kind: BackloadDeleteKind) -> HKSampleType {
        switch kind {
        case .sleepCategory: return HKCategoryType(.sleepAnalysis)
        case .stepQuantity: return HKQuantityType(.stepCount)
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

    /// Distance type a workout kind's distance is attached as; `nil` = no distance sample.
    static func distanceType(_ kind: BackloadWorkoutKind) -> HKQuantityType? {
        switch kind {
        case .running, .walking, .hiking: return HKQuantityType(.distanceWalkingRunning)
        case .cycling: return HKQuantityType(.distanceCycling)
        case .swimming: return HKQuantityType(.distanceSwimming)
        default: return nil
        }
    }

    static var allSampleTypes: Set<HKSampleType> {
        [
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
            HKQuantityType(.restingHeartRate), HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.vo2Max), HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType(),
            HKQuantityType(.heartRate), HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation),
            HKQuantityType(.heartRateVariabilitySDNN),
        ]
    }
}
#endif
