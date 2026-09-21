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
    /// v4 (B-30): the hub row's `updated_at` as epoch seconds, written as `HKMetadataKeySyncVersion`
    /// so a corrected hub value replaces the sample already in Health. Absent on the wire = nil.
    public var version: Int?
    public init(syncId: String, start: String, end: String, asleepSec: Double, deepSec: Double, lightSec: Double, remSec: Double, awakeSec: Double, stages: [BackloadSleepStageDTO] = [], version: Int? = nil) {
        self.syncId = syncId; self.start = start; self.end = end
        self.asleepSec = asleepSec; self.deepSec = deepSec; self.lightSec = lightSec; self.remSec = remSec; self.awakeSec = awakeSec
        self.stages = stages
        self.version = version
    }

    // Custom decode: `stages` defaults to `[]` when the key is absent, so a pre-v2 fixture (or a
    // hub response for a day outside the dense-series window) still decodes cleanly.
    enum CodingKeys: String, CodingKey { case syncId, start, end, asleepSec, deepSec, lightSec, remSec, awakeSec, stages, version }
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
        version = try c.decodeIfPresent(Int.self, forKey: .version)
    }
}

public struct BackloadRHREntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var bpm: Double
    public var version: Int?
    public init(syncId: String, date: String, bpm: Double, version: Int? = nil) { self.syncId = syncId; self.date = date; self.bpm = bpm; self.version = version }
}

public struct BackloadStepsEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var count: Double
    public var version: Int?
    public init(syncId: String, date: String, count: Double, version: Int? = nil) { self.syncId = syncId; self.date = date; self.count = count; self.version = version }
}

public struct BackloadEnergyEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var activeKcal: Double
    public var basalKcal: Double
    public var version: Int?
    public init(syncId: String, date: String, activeKcal: Double, basalKcal: Double, version: Int? = nil) {
        self.syncId = syncId; self.date = date; self.activeKcal = activeKcal; self.basalKcal = basalKcal; self.version = version
    }
}

public struct BackloadVo2MaxEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var value: Double
    public var version: Int?
    public init(syncId: String, date: String, value: Double, version: Int? = nil) { self.syncId = syncId; self.date = date; self.value = value; self.version = version }
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
    public var version: Int?
    /// W9 (B-30 P3, contract v3 additive, HT e7720ff): true for Garmin's indoor types
    /// (treadmill_running, indoor_cycling, …) -> `HKMetadataKeyIndoorWorkout`. Absent = nil.
    public var indoor: Bool?
    /// W9: the raw Garmin activity type (`core.activity.type`, e.g. `multi_sport`,
    /// `treadmill_running`) so the writer can refine `kind` itself. Absent = nil.
    public var rawType: String?
    public init(syncId: String, start: String, end: String, kind: BackloadWorkoutKindDTO, name: String, kcal: Double?, distanceM: Double?, avgHr: Double?, startEstimated: Bool? = nil, version: Int? = nil, indoor: Bool? = nil, rawType: String? = nil) {
        self.syncId = syncId; self.start = start; self.end = end; self.kind = kind; self.name = name
        self.kcal = kcal; self.distanceM = distanceM; self.avgHr = avgHr; self.startEstimated = startEstimated
        self.version = version
        self.indoor = indoor; self.rawType = rawType
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
    public var version: Int?
    public init(syncId: String, date: String, wakingAvg: Double?, sleepAvg: Double?, version: Int? = nil) {
        self.syncId = syncId; self.date = date; self.wakingAvg = wakingAvg; self.sleepAvg = sleepAvg; self.version = version
    }
}

public struct BackloadDailySpo2EntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var sleepAvg: Double?
    public var version: Int?
    public init(syncId: String, date: String, sleepAvg: Double?, version: Int? = nil) {
        self.syncId = syncId; self.date = date; self.sleepAvg = sleepAvg; self.version = version
    }
}

/// W9 (B-30 P5, contract v3 additive — HT e7720ff): daily floors climbed (`floors_ascended`).
public struct BackloadFloorsEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var count: Double
    public var version: Int?
    public init(syncId: String, date: String, count: Double, version: Int? = nil) { self.syncId = syncId; self.date = date; self.count = count; self.version = version }
}

/// W9 (B-30 P5): daily walking+running distance in metres, already NET of that day's workout
/// distance on the hub side (same double-count rule as `energy.active_kcal`) — the writer must
/// never re-subtract.
public struct BackloadDistanceEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var date: String
    public var meters: Double
    public var version: Int?
    public init(syncId: String, date: String, meters: Double, version: Int? = nil) { self.syncId = syncId; self.date = date; self.meters = meters; self.version = version }
}

/// W11 (B-30 P4, contract v4 additive — HT `feat/w11-activity-details`): one per-second heart-rate
/// reading from Garmin `activity/{id}/details`. `ts` is UTC ISO-8601 with `Z`.
public struct BackloadWorkoutHrSampleDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var bpm: Double
    public init(ts: String, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

/// W11: full-resolution HR for one activity — `sync_id` is the workout's (`workout:<activity_id>`),
/// `version` the hub's `fetched_at` epoch seconds. Only activities with ≥1 sample are sent.
public struct BackloadWorkoutHrEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var version: Int
    public var samples: [BackloadWorkoutHrSampleDTO]
    public init(syncId: String, version: Int, samples: [BackloadWorkoutHrSampleDTO]) {
        self.syncId = syncId; self.version = version; self.samples = samples
    }
}

/// W11: one GPS point of a workout route. `alt_m` / `speed_mps` are null on the wire when Garmin
/// served no elevation / speed for that second.
public struct BackloadWorkoutRoutePointDTO: Codable, Sendable, Equatable {
    public var ts: String
    public var lat: Double
    public var lon: Double
    public var altM: Double?
    public var speedMps: Double?
    public init(ts: String, lat: Double, lon: Double, altM: Double?, speedMps: Double?) {
        self.ts = ts; self.lat = lat; self.lon = lon; self.altM = altM; self.speedMps = speedMps
    }
}

/// W11: the route of one activity (only activities with ≥2 lat/lon points). `ascent_m` = the hub's
/// sum of positive `alt_m` deltas, null when no elevation column.
public struct BackloadWorkoutRouteEntryDTO: Codable, Sendable, Equatable {
    public var syncId: String
    public var version: Int
    public var ascentM: Double?
    public var points: [BackloadWorkoutRoutePointDTO]
    public init(syncId: String, version: Int, ascentM: Double?, points: [BackloadWorkoutRoutePointDTO]) {
        self.syncId = syncId; self.version = version; self.ascentM = ascentM; self.points = points
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
    /// W9 (B-30 P5) daily kinds — `[]` when a pre-W9 hub omits them.
    public var distance: [BackloadDistanceEntryDTO]
    public var floors: [BackloadFloorsEntryDTO]
    /// W11 (B-30 P4) dense per-workout series — `nil` when the hub omits them (a pre-W11 hub, or a
    /// `kinds=` filter without `workout_hr`/`workout_routes`), so every existing fixture still decodes.
    public var workoutHr: [BackloadWorkoutHrEntryDTO]?
    public var workoutRoutes: [BackloadWorkoutRouteEntryDTO]?
    public init(
        from: String, to: String, source: String,
        sleep: [BackloadSleepEntryDTO], rhr: [BackloadRHREntryDTO], steps: [BackloadStepsEntryDTO],
        energy: [BackloadEnergyEntryDTO], vo2max: [BackloadVo2MaxEntryDTO], workouts: [BackloadWorkoutEntryDTO],
        heartRate: [BackloadHeartRateEntryDTO] = [], respiration: [BackloadRespirationEntryDTO] = [],
        spo2: [BackloadSpo2EntryDTO] = [], hrv: [BackloadHrvEntryDTO] = [],
        stepBuckets: [BackloadStepBucketEntryDTO] = [], dailyResp: [BackloadDailyRespEntryDTO] = [],
        dailySpo2: [BackloadDailySpo2EntryDTO] = [],
        distance: [BackloadDistanceEntryDTO] = [], floors: [BackloadFloorsEntryDTO] = [],
        workoutHr: [BackloadWorkoutHrEntryDTO]? = nil, workoutRoutes: [BackloadWorkoutRouteEntryDTO]? = nil
    ) {
        self.from = from; self.to = to; self.source = source
        self.sleep = sleep; self.rhr = rhr; self.steps = steps; self.energy = energy; self.vo2max = vo2max; self.workouts = workouts
        self.heartRate = heartRate; self.respiration = respiration; self.spo2 = spo2; self.hrv = hrv
        self.stepBuckets = stepBuckets; self.dailyResp = dailyResp; self.dailySpo2 = dailySpo2
        self.distance = distance; self.floors = floors
        self.workoutHr = workoutHr; self.workoutRoutes = workoutRoutes
    }

    // Custom decode: the v2 dense/daily-fallback arrays default to `[]` when the hub omits them
    // (e.g. a `kinds=` filter that excludes every dense kind) rather than throwing keyNotFound.
    enum CodingKeys: String, CodingKey {
        case from, to, source, sleep, rhr, steps, energy, vo2max, workouts
        case heartRate, respiration, spo2, hrv, stepBuckets, dailyResp, dailySpo2
        case distance, floors
        case workoutHr, workoutRoutes
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
        distance = try c.decodeIfPresent([BackloadDistanceEntryDTO].self, forKey: .distance) ?? []
        floors = try c.decodeIfPresent([BackloadFloorsEntryDTO].self, forKey: .floors) ?? []
        workoutHr = try c.decodeIfPresent([BackloadWorkoutHrEntryDTO].self, forKey: .workoutHr)
        workoutRoutes = try c.decodeIfPresent([BackloadWorkoutRouteEntryDTO].self, forKey: .workoutRoutes)
    }
}
