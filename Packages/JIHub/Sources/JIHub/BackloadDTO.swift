import Foundation

// Backload contract v2 (frozen, docs/waves/cards/W2i.md — supersedes v1's W2h card): wire shape of
// `GET /api/v1/vitals/backload?from=YYYY-MM-DD&to=YYYY-MM-DD&kinds=`. snake_case wire format decoded
// via `JSON.decoder` (`.convertFromSnakeCase`) — property names spell the camelCase that strategy
// produces (`sync_id` -> `syncId`), per the convention in `HubDataProvider`'s other DTOs. Dates and
// timestamps stay `String` (no ISO-8601 decode strategy), same as every other DTO in this package;
// `JIHealthKit.BackloadMapper` parses them.

public struct BackloadSleepStageDTO: Codable, Sendable, Equatable {
    public var stage: BackloadSleepStageKindDTO
    public var start: String
    public var end: String
    public init(stage: BackloadSleepStageKindDTO, start: String, end: String) {
        self.stage = stage; self.start = start; self.end = end
    }
}

public enum BackloadSleepStageKindDTO: String, Codable, Sendable, Equatable {
    case deep, light, rem, awake
}

public struct BackloadSleepEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var start: String
    public var end: String
    public var asleepSec: Double
    public var deepSec: Double
    public var lightSec: Double
    public var remSec: Double
    public var awakeSec: Double
    /// v2: fine-grained stage intervals (empty when Garmin has none — pre-≈2026-04-15 days).
    public var stages: [BackloadSleepStageDTO]
    public init(syncId: String, start: String, end: String, asleepSec: Double, deepSec: Double, lightSec: Double, remSec: Double, awakeSec: Double, stages: [BackloadSleepStageDTO] = []) {
        self.syncId = syncId; self.start = start; self.end = end
        self.asleepSec = asleepSec; self.deepSec = deepSec; self.lightSec = lightSec; self.remSec = remSec; self.awakeSec = awakeSec
        self.stages = stages
    }

    // Custom decode: `stages` defaults to `[]` when the key is absent, so a pre-v2 fixture (or a
    // hub response for a day outside the dense-series window) still decodes cleanly.
    enum CodingKeys: String, CodingKey { case syncId, start, end, asleepSec, deepSec, lightSec, remSec, awakeSec, stages }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncId = try c.decode(String.self, forKey: .syncId)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decode(String.self, forKey: .end)
        asleepSec = try c.decode(Double.self, forKey: .asleepSec)
        deepSec = try c.decode(Double.self, forKey: .deepSec)
        lightSec = try c.decode(Double.self, forKey: .lightSec)
        remSec = try c.decode(Double.self, forKey: .remSec)
        awakeSec = try c.decode(Double.self, forKey: .awakeSec)
        stages = try c.decodeIfPresent([BackloadSleepStageDTO].self, forKey: .stages) ?? []
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
    /// v2: true when `start` is the 12:00 fallback (no `start_time_utc` from Garmin), false/absent
    /// when it's the real local activity start.
    public var startEstimated: Bool?
    public init(syncId: String, start: String, end: String, kind: BackloadWorkoutKindDTO, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?, startEstimated: Bool? = nil) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr; self.startEstimated = startEstimated
    }
}

/// v2 dense series — `heart_rate`/`respiration`/`spo2` carry no `sync_id` on the wire; the mapper
/// derives one from `ts` (see `BackloadMapper`).
public struct BackloadHeartRateEntryDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var bpm: Double
    public init(ts: String, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

public struct BackloadRespirationEntryDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var brpm: Double
    public init(ts: String, brpm: Double) { self.ts = ts; self.brpm = brpm }
}

public struct BackloadSpo2EntryDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var pct: Double
    public init(ts: String, pct: Double) { self.ts = ts; self.pct = pct }
}

public struct BackloadHrvReadingDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var rmssdMs: Double
    public init(ts: String, rmssdMs: Double) { self.ts = ts; self.rmssdMs = rmssdMs }
}

public struct BackloadHrvEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var nightlyRmssdMs: Double?
    public var readings: [BackloadHrvReadingDTO]
    public init(syncId: String, date: String, nightlyRmssdMs: Double?, readings: [BackloadHrvReadingDTO]) {
        self.syncId = syncId; self.date = date; self.nightlyRmssdMs = nightlyRmssdMs; self.readings = readings
    }
}

public struct BackloadStepBucketEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var start: String
    public var end: String
    public var count: Double
    public init(syncId: String, start: String, end: String, count: Double) {
        self.syncId = syncId; self.start = start; self.end = end; self.count = count
    }
}

public struct BackloadDailyRespEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var wakingAvg: Double?
    public var sleepAvg: Double?
    public init(syncId: String, date: String, wakingAvg: Double?, sleepAvg: Double?) {
        self.syncId = syncId; self.date = date; self.wakingAvg = wakingAvg; self.sleepAvg = sleepAvg
    }
}

public struct BackloadDailySpo2EntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var sleepAvg: Double?
    public init(syncId: String, date: String, sleepAvg: Double?) {
        self.syncId = syncId; self.date = date; self.sleepAvg = sleepAvg
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
    public var heartRate: [BackloadHeartRateEntryDTO]
    public var respiration: [BackloadRespirationEntryDTO]
    public var spo2: [BackloadSpo2EntryDTO]
    public var hrv: [BackloadHrvEntryDTO]
    public var stepBuckets: [BackloadStepBucketEntryDTO]
    public var dailyResp: [BackloadDailyRespEntryDTO]
    public var dailySpo2: [BackloadDailySpo2EntryDTO]
    public init(
        from: String, to: String, source: String,
        sleep: [BackloadSleepEntryDTO], rhr: [BackloadRHREntryDTO], steps: [BackloadStepsEntryDTO],
        energy: [BackloadEnergyEntryDTO], vo2max: [BackloadVo2MaxEntryDTO], workouts: [BackloadWorkoutEntryDTO],
        heartRate: [BackloadHeartRateEntryDTO] = [], respiration: [BackloadRespirationEntryDTO] = [],
        spo2: [BackloadSpo2EntryDTO] = [], hrv: [BackloadHrvEntryDTO] = [],
        stepBuckets: [BackloadStepBucketEntryDTO] = [], dailyResp: [BackloadDailyRespEntryDTO] = [],
        dailySpo2: [BackloadDailySpo2EntryDTO] = []
    ) {
        self.from = from; self.to = to; self.source = source
        self.sleep = sleep; self.rhr = rhr; self.steps = steps; self.energy = energy; self.vo2max = vo2max; self.workouts = workouts
        self.heartRate = heartRate; self.respiration = respiration; self.spo2 = spo2; self.hrv = hrv
        self.stepBuckets = stepBuckets; self.dailyResp = dailyResp; self.dailySpo2 = dailySpo2
    }

    // Custom decode: the v2 dense/daily-fallback arrays default to `[]` when the hub omits them
    // (e.g. a `kinds=` filter that excludes every dense kind) rather than throwing keyNotFound.
    enum CodingKeys: String, CodingKey {
        case from, to, source, sleep, rhr, steps, energy, vo2max, workouts
        case heartRate, respiration, spo2, hrv, stepBuckets, dailyResp, dailySpo2
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        source = try c.decode(String.self, forKey: .source)
        sleep = try c.decode([BackloadSleepEntryDTO].self, forKey: .sleep)
        rhr = try c.decode([BackloadRHREntryDTO].self, forKey: .rhr)
        steps = try c.decode([BackloadStepsEntryDTO].self, forKey: .steps)
        energy = try c.decode([BackloadEnergyEntryDTO].self, forKey: .energy)
        vo2max = try c.decode([BackloadVo2MaxEntryDTO].self, forKey: .vo2max)
        workouts = try c.decode([BackloadWorkoutEntryDTO].self, forKey: .workouts)
        heartRate = try c.decodeIfPresent([BackloadHeartRateEntryDTO].self, forKey: .heartRate) ?? []
        respiration = try c.decodeIfPresent([BackloadRespirationEntryDTO].self, forKey: .respiration) ?? []
        spo2 = try c.decodeIfPresent([BackloadSpo2EntryDTO].self, forKey: .spo2) ?? []
        hrv = try c.decodeIfPresent([BackloadHrvEntryDTO].self, forKey: .hrv) ?? []
        stepBuckets = try c.decodeIfPresent([BackloadStepBucketEntryDTO].self, forKey: .stepBuckets) ?? []
        dailyResp = try c.decodeIfPresent([BackloadDailyRespEntryDTO].self, forKey: .dailyResp) ?? []
        dailySpo2 = try c.decodeIfPresent([BackloadDailySpo2EntryDTO].self, forKey: .dailySpo2) ?? []
    }
}
