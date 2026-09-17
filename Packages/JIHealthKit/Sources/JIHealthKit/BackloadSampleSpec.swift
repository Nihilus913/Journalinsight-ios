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
    public init(syncId: String, start: Date, end: Date, kind: BackloadWorkoutKind, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr
    }
}

public enum BackloadWriteSpec: Sendable, Equatable {
    case quantity(BackloadQuantitySampleSpec)
    case sleep(BackloadSleepSampleSpec)
    case workout(BackloadWorkoutSampleSpec)

    public var syncId: String {
        switch self {
        case .quantity(let s): return s.syncId
        case .sleep(let s): return s.syncId
        case .workout(let s): return s.syncId
        }
    }
}
