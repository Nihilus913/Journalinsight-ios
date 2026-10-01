import Foundation

// W-B81 A-4: the Apple-workout half of `POST /api/v1/ingest/apple-health`. Frozen wire contract =
// HealthTraining `tests/fixtures/apple_workouts/{workouts_payload.json,README.md}` (copied into
// `JIHealthKitTests/Fixtures/apple_workouts/`; `AppleWorkoutUploadTests` pins the body to it).
// HK-free on purpose (like `HAEPayload.swift`): the HealthKit reader builds `AppleWorkoutRecord`s,
// everything below is plain values testable on any `swift test` host.

/// One workout as the HealthKit reader hands it over — units already converted (s, m, kcal, bpm),
/// dates still `Date`. `name == nil` = Health has none; the mapper derives one.
public struct AppleWorkoutRecord: Sendable, Equatable {
    public struct Activity: Sendable, Equatable {
        public var uuid: UUID
        public var sport: String
        public var name: String?
        public var start: Date
        public var end: Date
        public var durationS: Double
        public var distanceM: Double?
        public init(uuid: UUID, sport: String, name: String?, start: Date, end: Date, durationS: Double, distanceM: Double?) {
            self.uuid = uuid; self.sport = sport; self.name = name; self.start = start; self.end = end
            self.durationS = durationS; self.distanceM = distanceM
        }
    }

    public struct HRSample: Sendable, Equatable {
        public var ts: Date
        public var bpm: Double
        public init(ts: Date, bpm: Double) { self.ts = ts; self.bpm = bpm }
    }

    public struct RoutePoint: Sendable, Equatable {
        public var ts: Date
        public var lat: Double
        public var lon: Double
        public var elevationM: Double?
        public var speedMps: Double?
        public var hAccuracyM: Double?
        public init(ts: Date, lat: Double, lon: Double, elevationM: Double?, speedMps: Double?, hAccuracyM: Double?) {
            self.ts = ts; self.lat = lat; self.lon = lon; self.elevationM = elevationM; self.speedMps = speedMps; self.hAccuracyM = hAccuracyM
        }
    }

    public var uuid: UUID
    public var sport: String
    public var name: String?
    public var isIndoor: Bool?
    public var source: String?
    public var start: Date
    public var end: Date
    public var durationS: Double
    public var distanceM: Double?
    public var kcal: Double?
    public var avgHRBpm: Double?
    public var maxHRBpm: Double?
    public var effortUser: Double?
    public var effortEstimated: Double?
    /// Every `HKWorkoutActivity` (a simple Watch workout has exactly one).
    public var activities: [Activity]
    public var hrSamples: [HRSample]
    public var route: [RoutePoint]
    /// iOS 27 `HKWorkoutZoneGroup` for heart rate; `nil` = not present (omitted on the wire).
    public var zoneTime: [HAEWorkoutZoneTime]?

    public init(uuid: UUID, sport: String, name: String?, isIndoor: Bool?, source: String?, start: Date, end: Date,
                durationS: Double, distanceM: Double?, kcal: Double?, avgHRBpm: Double?, maxHRBpm: Double?,
                effortUser: Double?, effortEstimated: Double?, activities: [Activity], hrSamples: [HRSample],
                route: [RoutePoint], zoneTime: [HAEWorkoutZoneTime]?) {
        self.uuid = uuid; self.sport = sport; self.name = name; self.isIndoor = isIndoor; self.source = source
        self.start = start; self.end = end; self.durationS = durationS; self.distanceM = distanceM; self.kcal = kcal
        self.avgHRBpm = avgHRBpm; self.maxHRBpm = maxHRBpm; self.effortUser = effortUser; self.effortEstimated = effortEstimated
        self.activities = activities; self.hrSamples = hrSamples; self.route = route; self.zoneTime = zoneTime
    }
}

// MARK: - Wire types (snake_case keys, exact)

/// One workout on the wire. Scalar optionals are written as explicit `null` (the fixture's shape;
/// the hub treats null and absent alike); `zone_time` is omitted when Health has none.
public struct HAEWorkout: Encodable, Sendable, Equatable {
    public var uuid: String
    public var sport: String
    public var name: String?
    public var isIndoor: Bool?
    public var source: String?
    public var start: String
    public var end: String
    public var durationS: Int
    public var distanceM: Double?
    public var kcal: Double?
    public var avgHRBpm: Int?
    public var maxHRBpm: Int?
    public var effortUser: Double?
    public var effortEstimated: Double?
    public var isParent: Bool
    public var segmentCount: Int
    public var activities: [HAEWorkoutActivity]
    public var hrSamples: [HAEWorkoutHRSample]
    public var route: [HAEWorkoutRoutePoint]
    public var zoneTime: [HAEWorkoutZoneTime]?

    enum CodingKeys: String, CodingKey {
        case uuid, sport, name, source, start, end, kcal, activities, route
        case isIndoor = "is_indoor", durationS = "duration_s", distanceM = "distance_m"
        case avgHRBpm = "avg_hr_bpm", maxHRBpm = "max_hr_bpm", effortUser = "effort_user", effortEstimated = "effort_estimated"
        case isParent = "is_parent", segmentCount = "segment_count", hrSamples = "hr_samples", zoneTime = "zone_time"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid, forKey: .uuid)
        try c.encode(sport, forKey: .sport)
        try c.encode(name, forKey: .name)
        try c.encode(isIndoor, forKey: .isIndoor)
        try c.encode(source, forKey: .source)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(durationS, forKey: .durationS)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(kcal, forKey: .kcal)
        try c.encode(avgHRBpm, forKey: .avgHRBpm)
        try c.encode(maxHRBpm, forKey: .maxHRBpm)
        try c.encode(effortUser, forKey: .effortUser)
        try c.encode(effortEstimated, forKey: .effortEstimated)
        try c.encode(isParent, forKey: .isParent)
        try c.encode(segmentCount, forKey: .segmentCount)
        try c.encode(activities, forKey: .activities)
        try c.encode(hrSamples, forKey: .hrSamples)
        try c.encode(route, forKey: .route)
        try c.encodeIfPresent(zoneTime, forKey: .zoneTime)
    }
}

public struct HAEWorkoutActivity: Encodable, Sendable, Equatable {
    public var uuid: String
    public var sport: String
    public var name: String?
    public var start: String
    public var end: String
    public var durationS: Int
    public var distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case uuid, sport, name, start, end
        case durationS = "duration_s", distanceM = "distance_m"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid, forKey: .uuid)
        try c.encode(sport, forKey: .sport)
        try c.encode(name, forKey: .name)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(durationS, forKey: .durationS)
        try c.encode(distanceM, forKey: .distanceM)
    }
}

public struct HAEWorkoutHRSample: Encodable, Sendable, Equatable {
    public var ts: String
    public var bpm: Double
}

public struct HAEWorkoutRoutePoint: Encodable, Sendable, Equatable {
    public var ts: String
    public var lat: Double
    public var lon: Double
    public var elevationM: Double?
    public var speedMps: Double?
    public var hAccuracyM: Double?

    enum CodingKeys: String, CodingKey {
        case ts, lat, lon
        case elevationM = "elevation_m", speedMps = "speed_mps", hAccuracyM = "h_accuracy_m"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts, forKey: .ts)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(elevationM, forKey: .elevationM)
        try c.encode(speedMps, forKey: .speedMps)
        try c.encode(hAccuracyM, forKey: .hAccuracyM)
    }
}

public struct HAEWorkoutZoneTime: Encodable, Sendable, Equatable {
    public var zone: Int
    public var lowerBpm: Int?
    public var upperBpm: Int?
    public var seconds: Int

    public init(zone: Int, lowerBpm: Int?, upperBpm: Int?, seconds: Int) {
        self.zone = zone; self.lowerBpm = lowerBpm; self.upperBpm = upperBpm; self.seconds = seconds
    }

    enum CodingKeys: String, CodingKey {
        case zone, seconds
        case lowerBpm = "lower_bpm", upperBpm = "upper_bpm"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(zone, forKey: .zone)
        try c.encode(lowerBpm, forKey: .lowerBpm)
        try c.encode(upperBpm, forKey: .upperBpm)
        try c.encode(seconds, forKey: .seconds)
    }
}

// MARK: - Mapping

public enum AppleWorkoutMapper {
    /// Record → wire. Dates in `timeZone` (the device's local offset, never UTC — README).
    /// `is_parent` only for >1 activity; a simple workout's single activity is not a segment.
    public static func payload(_ r: AppleWorkoutRecord, timeZone: TimeZone) -> HAEWorkout {
        let fmt = { (d: Date) in HAEDate.format(d, timeZone: timeZone) }
        let segments = r.activities.count > 1 ? r.activities.sorted { $0.start < $1.start } : []
        return HAEWorkout(
            uuid: r.uuid.uuidString.uppercased(),
            sport: r.sport,
            name: r.name ?? derivedName(sport: r.sport, isIndoor: r.isIndoor),
            isIndoor: r.isIndoor,
            source: r.source,
            start: fmt(r.start), end: fmt(r.end),
            durationS: Int(r.durationS.rounded()),
            distanceM: r.distanceM, kcal: r.kcal,
            avgHRBpm: r.avgHRBpm.map { Int($0.rounded()) }, maxHRBpm: r.maxHRBpm.map { Int($0.rounded()) },
            effortUser: r.effortUser, effortEstimated: r.effortEstimated,
            isParent: !segments.isEmpty, segmentCount: segments.count,
            activities: segments.map {
                HAEWorkoutActivity(uuid: $0.uuid.uuidString.uppercased(), sport: $0.sport, name: $0.name, start: fmt($0.start),
                                   end: fmt($0.end), durationS: Int($0.durationS.rounded()), distanceM: $0.distanceM)
            },
            hrSamples: r.hrSamples.sorted { $0.ts < $1.ts }.map { HAEWorkoutHRSample(ts: fmt($0.ts), bpm: $0.bpm) },
            route: r.route.sorted { $0.ts < $1.ts }.map {
                HAEWorkoutRoutePoint(ts: fmt($0.ts), lat: $0.lat, lon: $0.lon, elevationM: $0.elevationM, speedMps: $0.speedMps, hAccuracyM: $0.hAccuracyM)
            },
            zoneTime: r.zoneTime
        )
    }

    /// "Indoor Run" / "Outdoor Run" / "Indoor Cycle"; no prefix when Health doesn't say.
    public static func derivedName(sport: String, isIndoor: Bool?) -> String {
        let short: [String: String] = ["running": "Run", "cycling": "Cycle", "walking": "Walk", "hiking": "Hike",
                                       "swimming": "Swim", "rowing": "Row"]
        let base = short[sport] ?? sport.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        switch isIndoor {
        case true?: return "Indoor \(base)"
        case false?: return "Outdoor \(base)"
        case nil: return base
        }
    }

    /// HealthKit zone durations → `zone_time`, numbered 1…n in the zones' index order, seconds and
    /// bounds rounded. Empty → `nil` (the key is then omitted).
    public static func zoneTimes(_ zones: [(index: Int, lower: Double?, upper: Double?, seconds: Double)]) -> [HAEWorkoutZoneTime]? {
        guard !zones.isEmpty else { return nil }
        return zones.sorted { $0.index < $1.index }.enumerated().map { i, z in
            HAEWorkoutZoneTime(zone: i + 1, lowerBpm: z.lower.map { Int($0.rounded()) }, upperBpm: z.upper.map { Int($0.rounded()) },
                               seconds: Int(z.seconds.rounded()))
        }
    }
}

/// Which Health workouts are NOT Apple workouts for the hub.
public enum AppleWorkoutFilter {
    /// `HealthKitBackloader` writes the hub's Garmin activities into Health under this app's own
    /// source with a `workout:<id>` sync identifier. Those already live in the hub as Garmin rows;
    /// uploading them back as dso 4 would count each session twice.
    public static func isHubBackload(fromThisApp: Bool, syncIdentifier: String?) -> Bool {
        fromThisApp && (syncIdentifier?.hasPrefix("workout:") ?? false)
    }

    /// Metadata key this app's DEBUG/test seeders put on what they write into Health (the sim has
    /// no Watch). Only seeders write it — never the backloader.
    public static let debugSeedMetadataKey = "JIDebugSeed"
}

#if canImport(HealthKit)
import HealthKit

extension AppleWorkoutFilter {
    /// Which HR samples join a workout's `hr_samples`: every source but this app (the Garmin
    /// backload's dense HR, written as this app, would leak into an Apple workout) — plus this
    /// app's samples marked `debugSeedMetadataKey`, so a seeded sim workout keeps its HR.
    /// `ownSource` = `HKQuery.predicateForObjects(from: HKSource.default())` (a parameter: the
    /// default source needs a bundle id, which a package test host has not).
    public static func workoutHeartRateSourcePredicate(ownSource: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(notPredicateWithSubpredicate: ownSource),
            HKQuery.predicateForObjects(withMetadataKey: debugSeedMetadataKey),
        ])
    }

    /// HR samples that START inside [start, end], both ends included: the Watch's last reading
    /// lands exactly on the workout's end instant (and counts in its max HR), which the half-open
    /// overlap window `predicateForSamples(withStart:end:options: [])` dropped.
    public static func workoutHeartRateWindowPredicate(start: Date, end: Date) -> NSPredicate {
        NSPredicate(format: "%K >= %@ AND %K <= %@",
                    HKPredicateKeyPathStartDate, start as NSDate, HKPredicateKeyPathStartDate, end as NSDate)
    }
}
#endif
