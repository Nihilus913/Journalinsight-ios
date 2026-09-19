import Foundation

// HK-free sample descriptions — `BackloadMapper` turns a `BackloadResponseDTO` into these, and
// `HealthKitBackloader` (behind `#if canImport(HealthKit)`) turns these into real `HKObject`s.
// Keeping this file HK-free is what lets `BackloadMapperTests` run on any `swift test` host.

public enum BackloadQuantityKind: Sendable, Equatable {
    case restingHeartRate   // bpm
    case stepCount          // count
    case activeEnergyBurned // kcal
    case basalEnergyBurned  // kcal
    case vo2Max             // mL/(kg·min)
    // v2 dense/daily-fallback kinds:
    case heartRate          // count/min, `heartRate` HK type (distinct from `restingHeartRate`)
    case respiratoryRate    // count/min (breaths/min)
    case oxygenSaturation   // fraction 0–1
    case hrvRMSSD           // ms — Garmin RMSSD, written under Apple's native iOS-27
                            // `heartRateVariabilityRMSSD` type (v4, audit D7). Before v4 these
                            // went into `heartRateVariabilitySDNN` behind a Settings toggle;
                            // RMSSD and SDNN are different statistics, and Apple's own Vitals
                            // daytime HRV is RMSSD, so the two series finally line up.
    // W9 (B-30 P5) daily kinds from `import.garmin_api_daily`:
    case flightsClimbed         // count — Garmin `floors_ascended`
    case distanceWalkingRunning // m — daily distance NET of workout distance (hub-side; never re-subtracted)
}

/// v4 (B-30): the hub row's `updated_at` as epoch seconds, carried onto every spec a DAILY item
/// produces and written as `HKMetadataKeySyncVersion`. HealthKit replaces a same-sync-id object
/// whose stored version is lower, so a corrected hub value overwrites a partial-day first write
/// (audit D4). `nil` on dense samples and sleep stages — those have no hub version.

public struct BackloadQuantitySampleSpec: Sendable, Equatable {
    public var syncId: String
    public var kind: BackloadQuantityKind
    public var start: Date
    public var end: Date
    public var value: Double
    public var version: Int?
    public init(syncId: String, kind: BackloadQuantityKind, start: Date, end: Date, value: Double, version: Int? = nil) {
        self.syncId = syncId; self.kind = kind; self.start = start; self.end = end; self.value = value
        self.version = version
    }
}

/// One contiguous asleep interval (start → end − awakeSec), per the frozen contract note: stage
/// totals from the hub are NOT written as fake back-to-back intervals — only `inBed` and one
/// `asleepUnspecified` block.
public struct BackloadSleepSampleSpec: Sendable, Equatable {
    public var syncId: String
    public var inBedStart: Date
    public var inBedEnd: Date
    public var asleepStart: Date
    public var asleepEnd: Date
    public var version: Int?
    public init(syncId: String, inBedStart: Date, inBedEnd: Date, asleepStart: Date, asleepEnd: Date, version: Int? = nil) {
        self.syncId = syncId; self.inBedStart = inBedStart; self.inBedEnd = inBedEnd
        self.asleepStart = asleepStart; self.asleepEnd = asleepEnd
        self.version = version
    }
}

public enum BackloadWorkoutKind: String, Sendable, Equatable {
    case strength, running, cycling, walking, hiking, swimming, other
}

/// W9 (B-30 P3): one dense heart-rate reading that falls inside a workout's window — the HK-free
/// shape of the `(Date, Double)` pair `WorkoutHRAttacher` turns into an `HKQuantitySample`.
public struct BackloadWorkoutHRSample: Sendable, Equatable {
    public var ts: Date
    public var bpm: Double
    public init(ts: Date, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

public struct BackloadWorkoutSampleSpec: Sendable, Equatable {
    public var syncId: String
    public var start: Date
    public var end: Date
    public var kind: BackloadWorkoutKind
    public var name: String
    public var kcal: Double?
    public var distanceM: Double?
    public var avgHr: Double?
    /// v2: true when `start` is the hub's 12:00 fallback rather than a real activity start.
    public var startEstimated: Bool
    public var version: Int?
    /// v5 (W9 P3): the raw Garmin activity type from the hub (`nil` from a pre-v3 hub).
    public var rawType: String?
    /// v5: `HKMetadataKeyIndoorWorkout` — true iff the hub flagged the row indoor.
    public var indoor: Bool
    /// v5: the run's dense HR readings inside `[start, end]`, in time order; `[]` when Garmin has
    /// none for the window (the workout is still written — just without an HR chart).
    public var hrSamples: [BackloadWorkoutHRSample]
    public init(syncId: String, start: Date, end: Date, kind: BackloadWorkoutKind, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?, startEstimated: Bool = false, version: Int? = nil, rawType: String? = nil, indoor: Bool = false, hrSamples: [BackloadWorkoutHRSample] = []) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr; self.startEstimated = startEstimated
        self.version = version
        self.rawType = rawType; self.indoor = indoor; self.hrSamples = hrSamples
    }
}

public enum BackloadSleepStageKind: Sendable, Equatable {
    case deep, light, rem, awake
}

public struct BackloadSleepStageSampleSpec: Sendable, Equatable {
    public var syncId: String
    public var stage: BackloadSleepStageKind
    public var start: Date
    public var end: Date
    public init(syncId: String, stage: BackloadSleepStageKind, start: Date, end: Date) {
        self.syncId = syncId; self.stage = stage; self.start = start; self.end = end
    }
}

/// v2 staged sleep: `inBed` interval + per-stage intervals, emitted instead of `.sleep` when the
/// hub returns non-empty `stages` for the night. The writer must delete the v1
/// `<baseSyncId>:asleep` marker before saving these (see `BackloadWriteSpec.delete`) so a device
/// that already ran v1 doesn't keep a stray generic-asleep block alongside the staged ones.
public struct BackloadSleepStagedSampleSpec: Sendable, Equatable {
    public var baseSyncId: String
    public var inBedStart: Date
    public var inBedEnd: Date
    public var stages: [BackloadSleepStageSampleSpec]
    public var version: Int?
    public init(baseSyncId: String, inBedStart: Date, inBedEnd: Date, stages: [BackloadSleepStageSampleSpec], version: Int? = nil) {
        self.baseSyncId = baseSyncId; self.inBedStart = inBedStart; self.inBedEnd = inBedEnd; self.stages = stages
        self.version = version
    }
}

/// A legacy object to delete before v2 writes proceed (see `HealthStoreWriting.deleteObjects`).
public enum BackloadDeleteKind: Sendable, Equatable {
    case sleepCategory  // legacy `<date>:asleep` marker, superseded by staged stage intervals
    case stepQuantity   // legacy daily `steps:<date>` sample, superseded by 15-min buckets
}

public enum BackloadWriteSpec: Sendable, Equatable {
    case quantity(BackloadQuantitySampleSpec)
    case sleep(BackloadSleepSampleSpec)
    case sleepStaged(BackloadSleepStagedSampleSpec)
    case workout(BackloadWorkoutSampleSpec)
    case delete(kind: BackloadDeleteKind, syncId: String)

    public var syncId: String {
        switch self {
        case .quantity(let s): return s.syncId
        case .sleep(let s): return s.syncId
        case .sleepStaged(let s): return s.baseSyncId
        case .workout(let s): return s.syncId
        case .delete(_, let syncId): return syncId
        }
    }
}
