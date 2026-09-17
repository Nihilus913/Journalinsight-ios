import Foundation

// W2h contract (frozen, docs/waves/cards/W2h.md): wire shape of
// `GET /api/v1/health/backload?from=YYYY-MM-DD&to=YYYY-MM-DD`. snake_case wire format decoded via
// `JSON.decoder` (`.convertFromSnakeCase`) — property names spell the camelCase that strategy
// produces (`sync_id` -> `syncId`), per the convention in `HubDataProvider`'s other DTOs. Dates and
// timestamps stay `String` (no ISO-8601 decode strategy), same as every other DTO in this package;
// `JIHealthKit.BackloadMapper` parses them.

public struct BackloadSleepEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var start: String
    public var end: String
    public var asleepSec: Double
    public var deepSec: Double
    public var lightSec: Double
    public var remSec: Double
    public var awakeSec: Double
    public init(syncId: String, start: String, end: String, asleepSec: Double, deepSec: Double, lightSec: Double, remSec: Double, awakeSec: Double) {
        self.syncId = syncId; self.start = start; self.end = end
        self.asleepSec = asleepSec; self.deepSec = deepSec; self.lightSec = lightSec; self.remSec = remSec; self.awakeSec = awakeSec
    }
}

public struct BackloadRHREntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var bpm: Double
    public init(syncId: String, date: String, bpm: Double) { self.syncId = syncId; self.date = date; self.bpm = bpm }
}

public struct BackloadStepsEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var count: Double
    public init(syncId: String, date: String, count: Double) { self.syncId = syncId; self.date = date; self.count = count }
}

public struct BackloadEnergyEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var activeKcal: Double
    public var basalKcal: Double
    public init(syncId: String, date: String, activeKcal: Double, basalKcal: Double) {
        self.syncId = syncId; self.date = date; self.activeKcal = activeKcal; self.basalKcal = basalKcal
    }
}

public struct BackloadVo2MaxEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var value: Double
    public init(syncId: String, date: String, value: Double) { self.syncId = syncId; self.date = date; self.value = value }
}

public enum BackloadWorkoutKindDTO: String, Codable, Sendable, Equatable {
    case strength, running, cycling, walking, hiking, swimming, other
}

public struct BackloadWorkoutEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var start: String
    public var end: String
    public var kind: BackloadWorkoutKindDTO
    public var name: String
    public var kcal: Double?
    public var distanceM: Double?
    public var avgHr: Double?
    public init(syncId: String, start: String, end: String, kind: BackloadWorkoutKindDTO, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr
    }
}

public struct BackloadResponseDTO: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var source: String
    public var sleep: [BackloadSleepEntryDTO]
    public var rhr: [BackloadRHREntryDTO]
    public var steps: [BackloadStepsEntryDTO]
    public var energy: [BackloadEnergyEntryDTO]
    public var vo2max: [BackloadVo2MaxEntryDTO]
    public var workouts: [BackloadWorkoutEntryDTO]
    public init(from: String, to: String, source: String, sleep: [BackloadSleepEntryDTO], rhr: [BackloadRHREntryDTO], steps: [BackloadStepsEntryDTO], energy: [BackloadEnergyEntryDTO], vo2max: [BackloadVo2MaxEntryDTO], workouts: [BackloadWorkoutEntryDTO]) {
        self.from = from; self.to = to; self.source = source
        self.sleep = sleep; self.rhr = rhr; self.steps = steps; self.energy = energy; self.vo2max = vo2max; self.workouts = workouts
    }
}
