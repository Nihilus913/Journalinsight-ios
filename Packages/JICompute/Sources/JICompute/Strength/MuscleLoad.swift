import Foundation

/// B-90 p3 — per-muscle training load: acute (7 d) vs chronic (28 d) ratio, on device.
///
/// Swift twin of the hub oracle HT `app/training/muscle_load.py` (B-90 p2; GET
/// /api/v1/training/muscle-load). Both must reproduce HT `tests/fixtures/muscle_load.json`
/// (byte copy in Tests/…/Resources/golden). The Python module docstring is the contract; this
/// file follows it line for line. An *estimate* — no medical wording, no Bevel formulas.
///
/// Load unit = "kg-volume" (reps × kg), spread over muscles with the p1 `MuscleMap` weights:
/// - weighted set (weightKg > 0):        reps × weightKg × w
/// - bodyweight set (no / zero weight):  reps × 0.65 × bodyKg × w
/// - timed set (logger kind "timed"):    (durationS / 3) × 0.65 × bodyKg × w
/// - RPE is not used. bodyKg = latest weight on/before the set's day, else the earliest later
///   one; none at all → the set is skipped and counted (never guessed).
/// - cardio credit: hours × TE × w × 1000 for the types in `cardio` (TE missing/0 → 1.0).
/// - unmapped exercises are skipped and counted.
/// Dedupe: a Garmin activity with sets on the same day as a logged session whose time spans
/// overlap (± 15 min), or either side has no times, is the same workout → logged sets win.
/// Windows (asOf inclusive): acute = Σ days asOf-6…asOf; chronic = Σ days asOf-27…asOf / 28 × 7.
/// Bands < 0.8 low, 0.8…1.3 balanced, > 1.3 high. Status: not_enough_data (no load, or first
/// load later than asOf-27), no_recent_load (nothing in 28 d), ok.
public nonisolated enum MuscleLoad {
    public static let acuteDays = 7
    public static let chronicDays = 28
    public static let bandLow = 0.8
    public static let bandHigh = 1.3
    public static let bodyweightCoef = 0.65
    public static let secondsPerRep = 3.0
    public static let cardioScale = 1000.0
    public static let dedupeSlackMinutes = 15
    static let roundLoad = 1
    static let roundRatio = 2

    private static let run: [MuscleWeight] = [MuscleWeight(.quads, 1.0), MuscleWeight(.calves, 1.0), MuscleWeight(.glutes, 0.5)]
    /// Garmin activity type → muscles credited per hour × TE. Coarse on purpose; extend here and in
    /// the Python oracle together.
    public static let cardio: [String: [MuscleWeight]] = [
        "running": run, "treadmill_running": run, "trail_running": run, "track_running": run, "indoor_running": run,
    ]

    // MARK: inputs (snake_case JSON = the hub's `load_inputs` shape)

    public struct BodyWeight: Codable, Sendable, Equatable {
        public var date: String
        public var weightKg: Double?
        public init(date: String, weightKg: Double?) { self.date = date; self.weightKg = weightKg }
        enum CodingKeys: String, CodingKey { case date, weightKg = "weight_kg" }
    }

    /// One `core.exercise_set` row of a Garmin activity.
    public struct GarminSet: Codable, Sendable, Equatable {
        public var exerciseName: String?
        public var exerciseCategory: String?
        public var reps: Int?
        public var weightKg: Double?
        public init(exerciseName: String?, exerciseCategory: String?, reps: Int?, weightKg: Double?) {
            self.exerciseName = exerciseName; self.exerciseCategory = exerciseCategory; self.reps = reps; self.weightKg = weightKg
        }
        enum CodingKeys: String, CodingKey {
            case exerciseName = "exercise_name", exerciseCategory = "exercise_category", reps, weightKg = "weight_kg"
        }
    }

    /// One `core.activity` (Garmin), with its strength sets (empty for cardio).
    public struct Activity: Codable, Sendable, Equatable {
        public var id: Int
        public var date: String
        public var type: String?
        public var startUTC: String?
        public var durationSec: Int?
        public var teAerobic: Double?
        public var sets: [GarminSet]
        public init(id: Int, date: String, type: String?, startUTC: String?, durationSec: Int?, teAerobic: Double?, sets: [GarminSet]) {
            self.id = id; self.date = date; self.type = type; self.startUTC = startUTC
            self.durationSec = durationSec; self.teAerobic = teAerobic; self.sets = sets
        }
        enum CodingKeys: String, CodingKey {
            case id, date, type, startUTC = "start_utc", durationSec = "duration_sec", teAerobic = "te_aerobic", sets
        }
    }

    /// One `plan.strength_set_log` row (the app's logger).
    public struct LoggedSet: Codable, Sendable, Equatable {
        public var exerciseKey: String?
        public var kind: String?
        public var reps: Int?
        public var weightKg: Double?
        public var durationS: Double?
        public init(exerciseKey: String?, kind: String?, reps: Int?, weightKg: Double?, durationS: Double?) {
            self.exerciseKey = exerciseKey; self.kind = kind; self.reps = reps; self.weightKg = weightKg; self.durationS = durationS
        }
        enum CodingKeys: String, CodingKey { case exerciseKey = "exercise_key", kind, reps, weightKg = "weight_kg", durationS = "duration_s" }
    }

    /// One `plan.strength_session` with its sets.
    public struct LoggedSession: Codable, Sendable, Equatable {
        public var id: Int
        public var date: String
        public var startedAt: String?
        public var endedAt: String?
        public var sets: [LoggedSet]
        public init(id: Int, date: String, startedAt: String?, endedAt: String?, sets: [LoggedSet]) {
            self.id = id; self.date = date; self.startedAt = startedAt; self.endedAt = endedAt; self.sets = sets
        }
        enum CodingKeys: String, CodingKey { case id, date, startedAt = "started_at", endedAt = "ended_at", sets }
    }

    public struct Inputs: Codable, Sendable, Equatable {
        public var asOf: String
        public var bodyWeight: [BodyWeight]
        public var activities: [Activity]
        public var loggedSessions: [LoggedSession]
        public init(asOf: String, bodyWeight: [BodyWeight] = [], activities: [Activity] = [], loggedSessions: [LoggedSession] = []) {
            self.asOf = asOf; self.bodyWeight = bodyWeight; self.activities = activities; self.loggedSessions = loggedSessions
        }
        enum CodingKeys: String, CodingKey { case asOf = "as_of", bodyWeight = "body_weight", activities, loggedSessions = "logged_sessions" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            asOf = try c.decode(String.self, forKey: .asOf)
            bodyWeight = try c.decodeIfPresent([BodyWeight].self, forKey: .bodyWeight) ?? []
            activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? []
            loggedSessions = try c.decodeIfPresent([LoggedSession].self, forKey: .loggedSessions) ?? []
        }
    }

    // MARK: output (same JSON as the hub route)

    public enum Status: String, Codable, Sendable { case ok, notEnoughData = "not_enough_data", noRecentLoad = "no_recent_load" }
    public enum Band: String, Codable, Sendable { case low, balanced, high }

    public struct MuscleRow: Codable, Sendable, Equatable {
        public var muscle: String
        public var name: String
        public var status: Status
        public var acute: Double
        public var chronic: Double
        public var ratio: Double?
        public var band: Band?
        public var firstLoad: String?
        public var lastLoad: String?
        enum CodingKeys: String, CodingKey {
            case muscle, name, status, acute, chronic, ratio, band, firstLoad = "first_load", lastLoad = "last_load"
        }
        public func encode(to encoder: any Encoder) throws { // nulls kept, as the hub sends them
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(muscle, forKey: .muscle); try c.encode(name, forKey: .name); try c.encode(status, forKey: .status)
            try c.encode(acute, forKey: .acute); try c.encode(chronic, forKey: .chronic); try c.encode(ratio, forKey: .ratio)
            try c.encode(band, forKey: .band); try c.encode(firstLoad, forKey: .firstLoad); try c.encode(lastLoad, forKey: .lastLoad)
        }
    }

    public struct Method: Codable, Sendable, Equatable {
        public struct Bands: Codable, Sendable, Equatable {
            public var lowBelow: Double, highAbove: Double
            enum CodingKeys: String, CodingKey { case lowBelow = "low_below", highAbove = "high_above" }
        }
        public var acuteDays: Int, chronicDays: Int, bands: Bands
        public var bodyweightCoef: Double, secondsPerRep: Double, cardioScale: Double, unit: String
        enum CodingKeys: String, CodingKey {
            case acuteDays = "acute_days", chronicDays = "chronic_days", bands, bodyweightCoef = "bodyweight_coef"
            case secondsPerRep = "seconds_per_rep", cardioScale = "cardio_scale", unit
        }
        public static let current = Method(acuteDays: MuscleLoad.acuteDays, chronicDays: MuscleLoad.chronicDays,
                                           bands: Bands(lowBelow: MuscleLoad.bandLow, highAbove: MuscleLoad.bandHigh),
                                           bodyweightCoef: MuscleLoad.bodyweightCoef, secondsPerRep: MuscleLoad.secondsPerRep,
                                           cardioScale: MuscleLoad.cardioScale, unit: "kg_volume")
    }

    public struct Skipped: Codable, Sendable, Equatable {
        public var unmappedSets: Int, bodyweightSetsNoWeight: Int
        enum CodingKeys: String, CodingKey { case unmappedSets = "unmapped_sets", bodyweightSetsNoWeight = "bodyweight_sets_no_weight" }
    }

    public struct Output: Codable, Sendable, Equatable {
        public var asOf: String
        public var estimate: Bool
        public var method: Method
        public var muscles: [MuscleRow]
        public var dedupedGarminActivities: [Int]
        public var skipped: Skipped
        enum CodingKeys: String, CodingKey {
            case asOf = "as_of", estimate, method, muscles, dedupedGarminActivities = "deduped_garmin_activities", skipped
        }
        public func row(_ m: Muscle) -> MuscleRow? { muscles.first { $0.muscle == m.rawValue } }
    }

    public static func band(_ ratio: Double?) -> Band? {
        guard let ratio else { return nil }
        if ratio < bandLow { return .low }
        if ratio > bandHigh { return .high }
        return .balanced
    }

    // MARK: compute

    public static func compute(_ inputs: Inputs) -> Output? {
        guard let asOf = Day(inputs.asOf) else { return nil }
        let bw = BodyWeightLookup(inputs.bodyWeight)
        let logged = inputs.loggedSessions.compactMap { s in Day(s.date).flatMap { $0 <= asOf ? (s, $0) : nil } }
        let acts = inputs.activities.compactMap { a in Day(a.date).flatMap { $0 <= asOf ? (a, $0) : nil } }

        var daily = Daily()
        var skipped = Skipped(unmappedSets: 0, bodyweightSetsNoWeight: 0)
        var dropped: [Int] = []

        func strength(_ day: Day, _ weights: [MuscleWeight]?, reps: Int?, weightKg: Double?, durationS: Double? = nil, timed: Bool = false) {
            guard let weights else { skipped.unmappedSets += 1; return }
            if timed {
                guard let durationS, durationS > 0 else { return }
                guard let kg = bw.on(day) else { skipped.bodyweightSetsNoWeight += 1; return }
                daily.add(day, weights, durationS / secondsPerRep * bodyweightCoef * kg)
                return
            }
            guard let reps, reps > 0 else { return }
            if let weightKg, weightKg > 0 {
                daily.add(day, weights, Double(reps) * weightKg)
                return
            }
            guard let kg = bw.on(day) else { skipped.bodyweightSetsNoWeight += 1; return }
            daily.add(day, weights, Double(reps) * bodyweightCoef * kg)
        }

        for (s, day) in logged {
            for x in s.sets {
                strength(day, MuscleMap.weights(forExercise: x.exerciseKey ?? ""), reps: x.reps, weightKg: x.weightKg,
                         durationS: x.durationS, timed: x.kind == "timed")
            }
        }

        for (a, day) in acts {
            if !a.sets.isEmpty {
                if logged.contains(where: { overlaps(a, day, $0.0, $0.1) }) {
                    dropped.append(a.id)
                    continue
                }
                for x in a.sets {
                    strength(day, MuscleMap.weights(forGarminName: x.exerciseName, category: x.exerciseCategory),
                             reps: x.reps, weightKg: x.weightKg)
                }
            }
            if let credit = cardio[(a.type ?? "").lowercased()], let dur = a.durationSec, dur != 0 {
                let te = (a.teAerobic ?? 0) == 0 ? 1.0 : a.teAerobic!
                daily.add(day, credit, Double(dur) / 3600.0 * te * cardioScale)
            }
        }

        let acuteFrom = asOf.adding(-(acuteDays - 1))
        let chronicFrom = asOf.adding(-(chronicDays - 1))
        let rows: [MuscleRow] = Muscle.allCases.map { m in
            let days = (daily.byMuscle[m] ?? []).filter { $0.value > 0 }
            let acute = days.filter { $0.day >= acuteFrom }.reduce(0.0) { $0 + $1.value }
            let chronic = days.filter { $0.day >= chronicFrom }.reduce(0.0) { $0 + $1.value } / Double(chronicDays) * Double(acuteDays)
            let first = days.map(\.day).min()
            let last = days.map(\.day).max()
            var ratio: Double?
            let status: Status
            if first == nil || first! > chronicFrom {
                status = .notEnoughData
            } else if chronic <= 0 {
                status = .noRecentLoad
            } else {
                status = .ok
                ratio = pyRound(acute / chronic, roundRatio)
            }
            return MuscleRow(muscle: m.rawValue, name: m.displayName, status: status,
                             acute: pyRound(acute, roundLoad), chronic: pyRound(chronic, roundLoad),
                             ratio: ratio, band: band(ratio), firstLoad: first?.iso, lastLoad: last?.iso)
        }
        return Output(asOf: asOf.iso, estimate: true, method: .current, muscles: rows,
                      dedupedGarminActivities: dropped.sorted(), skipped: skipped)
    }

    // MARK: helpers

    /// Same workout? Same day, and spans overlap ± slack — or either side has no times.
    static func overlaps(_ a: Activity, _ aDay: Day, _ s: LoggedSession, _ sDay: Day) -> Bool {
        guard aDay == sDay else { return false }
        guard let a0 = parseTime(a.startUTC), let s0 = parseTime(s.startedAt), let dur = a.durationSec, dur != 0 else { return true }
        let a1 = a0.addingTimeInterval(Double(dur))
        let s1 = parseTime(s.endedAt) ?? s0
        let slack = Double(dedupeSlackMinutes * 60)
        return a0 <= s1.addingTimeInterval(slack) && s0 <= a1.addingTimeInterval(slack)
    }

    /// ISO-8601 instant; "Z" or ±hh:mm offset, optional fractional seconds; no offset → UTC
    /// (as Python's `fromisoformat` + the oracle's UTC default).
    static func parseTime(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for candidate in [s, s.replacingOccurrences(of: " ", with: "T"), s.replacingOccurrences(of: " ", with: "T") + "Z"] {
            if let d = full.date(from: candidate) ?? frac.date(from: candidate) { return d }
        }
        return nil
    }

    /// Python `round(x, n)` (half-to-even) for the values this module produces.
    static func pyRound(_ x: Double, _ digits: Int) -> Double {
        let p = pow(10.0, Double(digits))
        return (x * p).rounded(.toNearestOrEven) / p
    }

    /// A calendar day as a proleptic-Gregorian day number (no time zones involved).
    struct Day: Comparable, Hashable, Sendable {
        let n: Int
        init(n: Int) { self.n = n }
        /// "yyyy-MM-dd…" (the first 10 characters, as the oracle's `_d`).
        init?(_ s: String) {
            let p = s.prefix(10).split(separator: "-")
            guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m), (1...31).contains(d) else { return nil }
            let yy = m <= 2 ? y - 1 : y
            let era = (yy >= 0 ? yy : yy - 399) / 400
            let yoe = yy - era * 400
            let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            n = era * 146097 + doe - 719468
        }
        func adding(_ days: Int) -> Day { Day(n: n + days) }
        var iso: String {
            let z = n + 719468
            let era = (z >= 0 ? z : z - 146096) / 146097
            let doe = z - era * 146097
            let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            let mp = (5 * doy + 2) / 153
            let d = doy - (153 * mp + 2) / 5 + 1
            let m = mp < 10 ? mp + 3 : mp - 9
            let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        static func < (a: Day, b: Day) -> Bool { a.n < b.n }
    }

    /// Per-muscle day totals in first-seen order (the oracle's dict order, so float sums match).
    struct Daily {
        var byMuscle: [Muscle: [(day: Day, value: Double)]] = [:]
        mutating func add(_ day: Day, _ weights: [MuscleWeight], _ units: Double) {
            for w in weights {
                var list = byMuscle[w.muscle] ?? []
                if let i = list.firstIndex(where: { $0.day == day }) { list[i].value += units * w.weight }
                else { list.append((day, units * w.weight)) }
                byMuscle[w.muscle] = list
            }
        }
    }

    struct BodyWeightLookup {
        let rows: [(day: Day, kg: Double)]
        init(_ raw: [BodyWeight]) {
            rows = raw.compactMap { r in
                guard let kg = r.weightKg, kg != 0, let d = Day(r.date) else { return nil }
                return (d, kg)
            }.sorted { ($0.day, $0.kg) < ($1.day, $1.kg) }
        }
        func on(_ day: Day) -> Double? {
            rows.last(where: { $0.day <= day })?.kg ?? rows.first?.kg
        }
    }
}
