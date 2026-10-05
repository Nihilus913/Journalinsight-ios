import Foundation

/// B-90 p4 — Muscle Freshness: Recovered / Fatigued / Depleted per muscle (an ESTIMATE).
/// Python oracle: HT `app/training/muscle_freshness.py`; both reproduce HT
/// `tests/fixtures/muscle_freshness.json` (byte copy in Tests/…/Resources/golden).
/// Our own heuristic (Bevel's is not public); thresholds unvalidated → every row is an estimate.
///
/// Input: workouts with per-muscle load (B-90 units, `MuscleLoad`/`muscle_load`). Only workouts
/// at or before `asOf` count; a muscle has a workout when its load is > 0.
/// < 3 workouts → `.notEnoughData` (never a guess). Else window = 72 h when the last load is
/// above the muscle's own P75, else 48 h; recovered ≥ window, fatigued ≥ window/2, else depleted.
public nonisolated enum MuscleFreshness {
    public static let calibrationWorkouts = 3
    public static let moderateHours = 48.0
    public static let heavyHours = 72.0
    public static let fatiguedFraction = 0.5

    public enum Status: String, Sendable, Equatable {
        case recovered, fatigued, depleted
        case notEnoughData = "not_enough_data"
    }

    public struct Workout: Sendable, Equatable {
        public let id: String
        public let at: Date
        public let loads: [String: Double]  // muscle raw key → load units
        public init(id: String, at: Date, loads: [String: Double]) { self.id = id; self.at = at; self.loads = loads }
        public init(id: String, at: Date, loads: [Muscle: Double]) {
            self.init(id: id, at: at, loads: Dictionary(uniqueKeysWithValues: loads.map { ($0.key.rawValue, $0.value) }))
        }
    }

    public struct Row: Sendable, Equatable {
        public let muscle: Muscle
        public let status: Status
        public let workouts: Int
        public let lastAt: Date?
        public let hoursSince: Double?
        public let lastLoad: Double?
        public let medianLoad: Double?
        public let p75Load: Double?
        public let loadVsMedian: Double?
        public let recoveryHours: Double?
        public var calibrationNeeded: Int { MuscleFreshness.calibrationWorkouts }
        public let label = "estimate"
    }

    public struct Result: Sendable, Equatable {
        public let asOf: Date
        public let unknownMuscles: Int
        public let muscles: [Row]  // one per Muscle.allCases, vocabulary order
        public func row(_ m: Muscle) -> Row? { muscles.first { $0.muscle == m } }
    }

    /// Linear-interpolated quantile (numpy 'linear'); `xs` non-empty.
    public static func quantile(_ xs: [Double], _ q: Double) -> Double {
        let s = xs.sorted()
        let pos = q * Double(s.count - 1)
        let lo = Int(pos)
        let hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    static func state(_ muscle: Muscle, _ history: [(at: Date, load: Double)], asOf: Date) -> Row {
        let n = history.count
        // First maximum by time, as Python's max().
        var last: (at: Date, load: Double)?
        for h in history where last == nil || h.at > last!.at { last = h }
        guard let last else {
            return Row(muscle: muscle, status: .notEnoughData, workouts: 0, lastAt: nil, hoursSince: nil,
                       lastLoad: nil, medianLoad: nil, p75Load: nil, loadVsMedian: nil, recoveryHours: nil)
        }
        let hours = asOf.timeIntervalSince(last.at) / 3600
        guard n >= calibrationWorkouts else {
            return Row(muscle: muscle, status: .notEnoughData, workouts: n, lastAt: last.at, hoursSince: hours,
                       lastLoad: last.load, medianLoad: nil, p75Load: nil, loadVsMedian: nil, recoveryHours: nil)
        }
        let loads = history.map(\.load)
        let median = quantile(loads, 0.5), p75 = quantile(loads, 0.75)
        let window = last.load > p75 ? heavyHours : moderateHours
        let status: Status = hours >= window ? .recovered : hours >= window * fatiguedFraction ? .fatigued : .depleted
        return Row(muscle: muscle, status: status, workouts: n, lastAt: last.at, hoursSince: hours,
                   lastLoad: last.load, medianLoad: median, p75Load: p75,
                   loadVsMedian: median > 0 ? last.load / median : nil, recoveryHours: window)
    }

    public static func compute(workouts: [Workout], asOf: Date) -> Result {
        var hist: [Muscle: [(at: Date, load: Double)]] = [:]
        var unknown = 0
        for w in workouts where w.at <= asOf {
            // Sorted keys: deterministic like Python's insertion order is irrelevant to the maths.
            for (key, load) in w.loads.sorted(by: { $0.key < $1.key }) {
                guard let m = Muscle(rawValue: key) else { unknown += 1; continue }
                if load > 0 { hist[m, default: []].append((w.at, load)) }
            }
        }
        return Result(asOf: asOf, unknownMuscles: unknown,
                      muscles: Muscle.allCases.map { state($0, hist[$0] ?? [], asOf: asOf) })
    }
}
