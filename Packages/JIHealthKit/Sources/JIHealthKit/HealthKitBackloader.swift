#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore
import JIHub

/// `BackloadRunning` (JICore, frozen) implementation: fetches month chunks from the hub via
/// `BackloadClient`, maps them through `BackloadMapper`, and writes new samples through a
/// `HealthStoreWriting` (real `HKHealthStore` in the app, a fake in tests). Idempotent — every
/// write carries `HKMetadataKeySyncIdentifier` + `HKMetadataKeySyncVersion` (v4: the hub row's
/// `updated_at`), and each month's existing ids AND their versions are queried before saving, so
/// a re-run of unchanged data writes 0 new samples while a corrected hub row replaces the sample
/// already in Health. Cursor (last fully-written day) persists in the
/// App-Group `UserDefaults` suite (`group.toby913.JournalInsight`, same suite as `SnapshotStore`)
/// under key `hk.backload.cursor`, so a killed/resumed run picks up where it left off.
public final class HealthKitBackloader: BackloadRunning, Sendable {
    private let hub: BackloadClient
    private let store: any HealthStoreWriting
    /// W9 L2 (B-30 P2.7): read seam the overlap policy queries for other sources' workouts.
    /// `nil` (test default) disables the check — every hub workout is written as before.
    private let reader: (any HealthStoreReading)?
    // UserDefaults is thread-safe by documented contract but predates Sendable annotation on
    // this SDK — same reasoning as `JISnapshot.SnapshotStore`.
    private nonisolated(unsafe) let cursorDefaults: UserDefaults?
    private static let cursorKey = "hk.backload.cursor"
    public static let appGroupSuite = "group.toby913.JournalInsight"

    public init(hub: BackloadClient, store: any HealthStoreWriting = RealHealthStore(), reader: (any HealthStoreReading)? = RealHealthStoreReader(), appGroupSuite: String = HealthKitBackloader.appGroupSuite) {
        self.hub = hub
        self.store = store
        self.reader = reader
        self.cursorDefaults = UserDefaults(suiteName: appGroupSuite)
    }

    /// Test seam: inject a `UserDefaults` double directly instead of routing through
    /// `UserDefaults(suiteName:)` (see `SnapshotStore`'s own note on why that initializer can't
    /// be trusted to return `nil` for a bogus suite name across toolchains).
    init(hub: BackloadClient, store: any HealthStoreWriting, reader: (any HealthStoreReading)? = nil, defaults: UserDefaults?) {
        self.hub = hub
        self.store = store
        self.reader = reader
        self.cursorDefaults = defaults
    }

    public func authorize() async throws {
        guard store.isHealthDataAvailable else { throw BackloadError.healthDataUnavailable }
        do {
            try await store.requestAuthorization(toShare: Self.allSampleTypes)
        } catch {
            throw BackloadError.authorizationDenied
        }
        // W9 L2: the overlap policy needs to READ other sources' workouts. A read decline is
        // never fatal (HealthKit then answers with our own objects only, which the reader
        // excludes -> nothing to overlap -> every hub workout is written as before).
        try? await reader?.requestAuthorization(toRead: [HKWorkoutType.workoutType()])
    }

    public func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
        // One-time upgrade: an older writer version walks the whole range again and rewrites
        // the kinds that changed shape (v3: workouts; v4: everything the hub re-versioned; v5:
        // see `V5Upgrade`) and, per chunk, deletes what an older writer mis-wrote
        // (`runV4Upgrade`, `runV5Upgrade`).
        let storedVersion = cursorDefaults?.integer(forKey: Self.writerVersionKey) ?? 0
        let needsUpgrade = storedVersion < Self.writerVersion
        if needsUpgrade { cursorDefaults?.removeObject(forKey: Self.cursorKey) }
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
            let chunkEnd = chunk.to.addingTimeInterval(86_399) // include the last day fully
            if needsUpgrade {
                if storedVersion < 4 { await runV4Upgrade(dto: dto, start: chunk.from, end: chunkEnd) }
                if storedVersion < 5 { await runV5Upgrade(dto: dto, start: chunk.from, end: chunkEnd) }
            }

            // W9 L2 (B-30 P2.7): hub workouts another source already covers > 50 % of are skipped
            // — and, if a pre-policy run wrote our copy, it is removed below so Health converges.
            let overlapSkipped = await overlapSkippedSyncIds(in: allSpecs, start: chunk.from, end: chunkEnd)

            // Deletions (v1 markers superseded by v2 writes) happen before the save pass so a
            // fresh `existingSyncVersions` read (below) never sees the object it's about to replace.
            var deletionsByKind: [BackloadDeleteKind: Set<String>] = [:]
            var writableSpecs: [BackloadWriteSpec] = []
            for spec in allSpecs {
                switch spec {
                case .delete(let kind, let syncId):
                    deletionsByKind[kind, default: []].insert(syncId)
                case .workout(let w) where overlapSkipped.contains(w.syncId):
                    skipped += 1
                    for entry in Self.objectEntries(for: spec) {
                        try? await store.deleteObjects(sampleType: entry.type, syncIdentifiers: [entry.syncId])
                        for sample in entry.associated {
                            if let sid = sample.metadata?[HKMetadataKeySyncIdentifier] as? String {
                                try? await store.deleteObjects(sampleType: sample.sampleType, syncIdentifiers: [sid])
                            }
                        }
                    }
                default:
                    writableSpecs.append(spec)
                }
            }
            for (kind, syncIds) in deletionsByKind {
                try? await store.deleteObjects(sampleType: Self.sampleType(for: kind), syncIdentifiers: syncIds)
            }

            let entries = writableSpecs.flatMap(Self.objectEntries(for:))
            let byType = Dictionary(grouping: entries, by: { ObjectIdentifier($0.type) })
            var existingByType: [ObjectIdentifier: [String: Int]] = [:]
            for (key, group) in byType {
                guard let sampleType = group.first?.type else { continue }
                existingByType[key] = (try? await store.existingSyncVersions(sampleType: sampleType, start: chunk.from, end: chunkEnd)) ?? [:]
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
                } else if let stored = existingByType[ObjectIdentifier(entry.type)]?[entry.syncId], stored >= entry.version {
                    // Only an object that is already at least as new as the hub's row is left
                    // alone; anything older is re-saved, and HealthKit replaces a same-sync-id
                    // object whose stored `HKMetadataKeySyncVersion` is lower (audit D4).
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

    // MARK: - v5 upgrade pass (W9)

    /// Per-lane steps of the writer v5 upgrade pass, run per chunk while the stored writer
    /// version is below 5. Each W9 lane adds one `case`; `runV5Upgrade` switches over all of them.
    // integrate: reconcile with L1's V5Upgrade (L1 defines the enum + `case workoutHR`; L2 adds `dailyKinds`)
    enum V5Upgrade: CaseIterable {
        /// L2 (B-30 P5): `floors` -> flightsClimbed and `distance` -> distanceWalkingRunning are
        /// additive daily kinds. Nothing in Health predates them, so there is nothing to delete —
        /// the cursor reset in `run` is what makes the walk start over and give every day its
        /// first floors/distance write through the normal version-keyed save path.
        case dailyKinds
    }

    private func runV5Upgrade(dto: BackloadResponseDTO, start: Date, end: Date) async {
        for step in V5Upgrade.allCases {
            switch step {
            case .dailyKinds:
                break // additive kinds: no deletion (see the case doc)
            }
        }
    }

    // MARK: - Overlap dedupe (W9 L2, B-30 P2.7)

    /// Sync ids of the hub workouts in `specs` that `WorkoutOverlapPolicy` rejects against the
    /// workouts other sources hold in `[start, end]`. Empty without a reader, or when the read
    /// fails — a query that can't run must never block the chunk's writes.
    private func overlapSkippedSyncIds(in specs: [BackloadWriteSpec], start: Date, end: Date) async -> Set<String> {
        guard let reader else { return [] }
        let hubWorkouts: [BackloadWorkoutSampleSpec] = specs.compactMap {
            if case .workout(let w) = $0 { return w } else { return nil }
        }
        guard !hubWorkouts.isEmpty, let foreign = try? await reader.workouts(start: start, end: end), !foreign.isEmpty else { return [] }
        let intervals = foreign.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return Set(hubWorkouts.filter { WorkoutOverlapPolicy.shouldSkip(start: $0.start, end: $0.end, existing: intervals) }.map(\.syncId))
    }

    // MARK: - v4 upgrade pass

    /// One-time cleanup of what writer v3 left in Health, run per chunk while the stored writer
    /// version is below `writerVersion` (audit 2026-09-18, D1/D3/D7):
    /// a) `steps:<date>:HHMM` buckets for days this chunk's dense response has NO buckets for —
    ///    Garmin returned all-zero buckets back to 2025-05-27 and the hub now drops those days,
    ///    so the daily `steps:<date>` sample (re-saved in the same run) stands for them again;
    /// b) `resp:*` samples at or below 0 breaths/min — Garmin's "no reading" sentinels (−1/−2);
    /// c) every `hrv:*` sample under the SDNN type — Garmin RMSSD, re-written under the native
    ///    RMSSD type by this same run.
    /// Failures are swallowed: a cleanup that can't run must never sink the chunk's writes.
    private func runV4Upgrade(dto: BackloadResponseDTO, start: Date, end: Date) async {
        let bucketDates = Set(dto.stepBuckets.compactMap { BackloadMapper.dateOnly($0.start) })
        _ = try? await store.deleteObjects(sampleType: HKQuantityType(.stepCount), start: start, end: end) { sample in
            guard let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                  let date = Self.stepBucketSyncIdDate(id) else { return false }
            return !bucketDates.contains(date)
        }
        _ = try? await store.deleteObjects(sampleType: HKQuantityType(.respiratoryRate), start: start, end: end) { sample in
            guard let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String, id.hasPrefix("resp:"),
                  let q = sample as? HKQuantitySample else { return false }
            return q.quantity.doubleValue(for: HKUnit(from: "count/min")) <= 0
        }
        _ = try? await store.deleteObjects(sampleType: HKQuantityType(.heartRateVariabilitySDNN), start: start, end: end) { sample in
            (sample.metadata?[HKMetadataKeySyncIdentifier] as? String)?.hasPrefix("hrv:") == true
        }
    }

    /// `"steps:2026-06-01:0100"` -> `"2026-06-01"`; `nil` for anything that isn't a 15-min step
    /// bucket id (notably the daily `"steps:2026-06-01"`, which must survive the pass).
    static func stepBucketSyncIdDate(_ syncId: String) -> String? {
        let parts = syncId.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "steps", parts[1].count == 10,
              parts[2].count == 4, parts[2].allSatisfy(\.isNumber) else { return nil }
        return String(parts[1])
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
            stepBuckets: dense.stepBuckets, dailyResp: daily.dailyResp, dailySpo2: daily.dailySpo2,
            distance: daily.distance, floors: daily.floors
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
        /// The `HKMetadataKeySyncVersion` written on `object` — compared against the version
        /// already in Health to decide save vs skip.
        let version: Int
        /// Samples to attach to `object` (an `HKWorkout`) after it is saved — see `HealthStoreWriting.add`.
        var associated: [HKSample] = []
    }

    /// Bumped when an already-written kind must be rewritten (HealthKit replaces objects whose
    /// `HKMetadataKeySyncIdentifier` matches and whose `HKMetadataKeySyncVersion` is higher).
    /// v3: workouts gain associated energy/distance samples so Fitness credits the rings.
    /// v4 (B-30): per-item hub versions, HRV under the native RMSSD type, and the one-time
    /// cleanup pass in `runV4Upgrade`.
    static let writerVersion = 4
    static let writerVersionKey = "hk.backload.writerVersion"
    static let workoutSyncVersion = 3
    static let lastCompletedKey = "hk.backload.lastCompletedDay"

    /// Custom metadata key for average heart rate on a workout — HealthKit has no standard
    /// per-workout average-HR metadata key (only per-sample `HKQuantitySample`s tied to a
    /// workout via `HKWorkoutBuilder` associations); stored here instead to keep the writer on
    /// the plain `save(_:)` seam rather than pulling the builder's async collection API into
    /// `HealthStoreWriting`.
    static let averageHeartRateMetadataKey = "HTAverageHeartRateBPM"

    /// Fallback `HKMetadataKeySyncVersion` for an item the hub sent no `version` for (dense
    /// series, and any hub older than B-30): 2 for samples, 3 for workouts — exactly what writer
    /// v2/v3 wrote, so a re-run of unchanged data still skips instead of churning.
    static let syncVersion = 2

    static func objectEntries(for spec: BackloadWriteSpec) -> [ObjectEntry] {
        switch spec {
        case .quantity(let q):
            guard let type = quantityType(q.kind) else { return [] }
            let version = q.version ?? syncVersion
            let metadata: [String: Any] = [HKMetadataKeySyncIdentifier: q.syncId, HKMetadataKeySyncVersion: version]
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: quantityUnit(q.kind), doubleValue: q.value), start: q.start, end: q.end, metadata: metadata)
            return [ObjectEntry(object: sample, type: type, syncId: q.syncId, version: version)]

        case .sleep(let s):
            let sleepType = HKCategoryType(.sleepAnalysis)
            let inBedId = "\(s.syncId):inbed"
            let asleepId = "\(s.syncId):asleep"
            let version = s.version ?? syncVersion
            let inBed = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: s.inBedStart, end: s.inBedEnd,
                metadata: [HKMetadataKeySyncIdentifier: inBedId, HKMetadataKeySyncVersion: version])
            let asleep = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: s.asleepStart, end: s.asleepEnd,
                metadata: [HKMetadataKeySyncIdentifier: asleepId, HKMetadataKeySyncVersion: version])
            return [
                ObjectEntry(object: inBed, type: sleepType, syncId: inBedId, version: version),
                ObjectEntry(object: asleep, type: sleepType, syncId: asleepId, version: version),
            ]

        case .sleepStaged(let s):
            let sleepType = HKCategoryType(.sleepAnalysis)
            let inBedId = "\(s.baseSyncId):inbed"
            let version = s.version ?? syncVersion
            let inBed = HKCategorySample(
                type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: s.inBedStart, end: s.inBedEnd,
                metadata: [HKMetadataKeySyncIdentifier: inBedId, HKMetadataKeySyncVersion: version])
            var out = [ObjectEntry(object: inBed, type: sleepType, syncId: inBedId, version: version)]
            for stage in s.stages {
                let sample = HKCategorySample(
                    type: sleepType, value: stageCategoryValue(stage.stage),
                    start: stage.start, end: stage.end,
                    metadata: [HKMetadataKeySyncIdentifier: stage.syncId, HKMetadataKeySyncVersion: version])
                out.append(ObjectEntry(object: sample, type: sleepType, syncId: stage.syncId, version: version))
            }
            return out

        case .workout(let w):
            let type = HKWorkoutType.workoutType()
            let version = w.version ?? workoutSyncVersion
            var metadata: [String: Any] = [HKMetadataKeySyncIdentifier: w.syncId, HKMetadataKeySyncVersion: version, HKMetadataKeyWorkoutBrandName: w.name]
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
                    metadata: [HKMetadataKeySyncIdentifier: "\(w.syncId):energy", HKMetadataKeySyncVersion: version]))
            }
            if let distance, let distanceType = distanceType(w.kind) {
                associated.append(HKQuantitySample(
                    type: distanceType, quantity: distance, start: w.start, end: w.end,
                    metadata: [HKMetadataKeySyncIdentifier: "\(w.syncId):distance", HKMetadataKeySyncVersion: version]))
            }
            return [ObjectEntry(object: workout, type: type, syncId: w.syncId, version: version, associated: associated)]

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
        // Resolved only through `HKReadKind` (HKTypes.swift owns the identifier string, and
        // `HKTypesTests.identifierIsolationSourceGrep` keeps it there); `nil` on a runtime
        // without the iOS-27 native type, which drops the HRV specs rather than mis-filing them.
        case .hrvRMSSD: return HKReadKind.hrvRMSSDQuantityType
        case .flightsClimbed: return HKQuantityType(.flightsClimbed)
        case .distanceWalkingRunning: return HKQuantityType(.distanceWalkingRunning)
        }
    }

    static func quantityUnit(_ kind: BackloadQuantityKind) -> HKUnit {
        switch kind {
        case .restingHeartRate, .heartRate, .respiratoryRate: return HKUnit(from: "count/min")
        case .stepCount, .flightsClimbed: return .count()
        case .distanceWalkingRunning: return .meter()
        case .activeEnergyBurned, .basalEnergyBurned: return .kilocalorie()
        case .vo2Max: return HKUnit(from: "ml/(kg*min)")
        case .oxygenSaturation: return .percent() // written as a 0–1 fraction, per HK convention
        case .hrvRMSSD: return HKUnit.secondUnit(with: .milli)
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

    /// Authorization set. The SDNN type stays in it after v4 — not to write under any more, but
    /// because `runV4Upgrade` has to be allowed to delete the `hrv:*` samples v3 put there.
    static var allSampleTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
            HKQuantityType(.restingHeartRate), HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.vo2Max), HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType(),
            HKQuantityType(.heartRate), HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.flightsClimbed), // W9 L2 (P5); distanceWalkingRunning is already above
        ]
        if let rmssd = HKReadKind.hrvRMSSDQuantityType { types.insert(rmssd) }
        return types
    }
}
#endif
