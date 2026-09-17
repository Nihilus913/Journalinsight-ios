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
    case hrvSDNN            // ms — `heartRateVariabilitySDNN`; Garmin RMSSD written under the
                             // Apple SDNN type per the v2 contract, gated by `hk.backload.writeHRV`
}

public struct BackloadQuantitySampleSpec: Sendable, Equatable {
    public var syncId: String
    public var kind: BackloadQuantityKind
    public var start: Date
    public var end: Date
    public var value: Double
    public init(syncId: String, kind: BackloadQuantityKind, start: Date, end: Date, value: Double) {
        self.syncId = syncId; self.kind = kind; self.start = start; self.end = end; self.value = value
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
    public init(syncId: String, inBedStart: Date, inBedEnd: Date, asleepStart: Date, asleepEnd: Date) {
        self.syncId = syncId; self.inBedStart = inBedStart; self.inBedEnd = inBedEnd
        self.asleepStart = asleepStart; self.asleepEnd = asleepEnd
    }
}

public enum BackloadWorkoutKind: String, Sendable, Equatable {
    case strength, running, cycling, walking, hiking, swimming, other
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
    public init(syncId: String, start: Date, end: Date, kind: BackloadWorkoutKind, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?, startEstimated: Bool = false) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr; self.startEstimated = startEstimated
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
    public init(baseSyncId: String, inBedStart: Date, inBedEnd: Date, stages: [BackloadSleepStageSampleSpec]) {
        self.baseSyncId = baseSyncId; self.inBedStart = inBedStart; self.inBedEnd = inBedEnd; self.stages = stages
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
