import Foundation
import JICompute

/// B-90 p5 — what the Muscles card / screen / detail sheet show, built from the phone's own
/// strength log with the p3 `MuscleLoad` (7 d vs 28 d) and p4 `MuscleFreshness` computes. Pure and
/// nonisolated so tests drive it with fixtures. Every number is an estimate; no data → no number.
nonisolated struct MusclesSession: Sendable, Equatable {
    var name: String?
    /// The session start (freshness clock).
    var at: Date
    var session: MuscleLoad.LoggedSession
}

nonisolated struct MusclesInput: Sendable, Equatable {
    var now: Date
    var sessions: [MusclesSession]
    var bodyWeight: [MuscleLoad.BodyWeight] = []
}

nonisolated enum MusclesPhase: Sendable, Equatable { case empty, calibrating, populated }

nonisolated enum MuscleState: Sendable, Equatable, Comparable {
    case depleted, fatigued, recovered
    /// Trained, but fewer than 3 workouts in 28 d (n = workouts so far, 1…2).
    case calibrating(Int)
    case noData

    var rank: Int {
        switch self {
        case .depleted: 0
        case .fatigued: 1
        case .recovered: 2
        case .calibrating: 3
        case .noData: 4
        }
    }

    static func < (a: MuscleState, b: MuscleState) -> Bool { a.rank < b.rank }

    var word: String {
        switch self {
        case .depleted: "Depleted"
        case .fatigued: "Fatigued"
        case .recovered: "Recovered"
        case .calibrating: "Calibrating"
        case .noData: "No data"
        }
    }
}

nonisolated struct MuscleCounted: Sendable, Equatable, Identifiable {
    var exercise: String
    var weight: Double
    var sets: Int
    var load: Double
    var id: String { exercise }
    var creditLine: String { "\(weight >= 1 ? "Primary" : "Secondary") × \(musclesNumber(weight, 1)) · \(sets) set\(sets == 1 ? "" : "s")" }
}

nonisolated struct MuscleRowSummary: Sendable, Equatable, Identifiable {
    var muscle: Muscle
    var state: MuscleState
    var workouts: Int
    var lastAt: Date?
    var hoursSince: Double?
    var lastSessionName: String?
    var lastLoad: Double?
    var medianLoad: Double?
    var aboveP75: Bool
    var recoveryHours: Double?
    /// 7 d sum / 28 d mean × 7 (reps × kg). Ratio nil until the muscle has 28 d of history.
    var acute: Double
    var chronic: Double
    var ratio: Double?
    var band: MuscleLoad.Band?
    var counted: [MuscleCounted]
    var id: String { muscle.rawValue }
    var name: String { muscle.displayName }

    /// Fresh-by estimate: last load + the rule's window (only while not yet recovered).
    var freshBy: Date? {
        guard state == .depleted || state == .fatigued, let lastAt, let recoveryHours else { return nil }
        return lastAt.addingTimeInterval(recoveryHours * 3600)
    }

    var bandWord: String? {
        switch band {
        case .low: "Low"
        case .balanced: "Productive"
        case .high: "Overreaching"
        case nil: nil
        }
    }
}

nonisolated struct MusclesSummary: Sendable, Equatable {
    var phase: MusclesPhase
    var rows: [MuscleRowSummary]
    var lastSessionName: String?
    var lastSessionAt: Date?
    var asOf: Date

    /// The most advanced calibration among trained muscles (0 when nothing is trained).
    var calibrationProgress: Int { min(MuscleFreshness.calibrationWorkouts, rows.map(\.workouts).max() ?? 0) }

    /// The map colour per drawn shape: the worst state among the vocabulary muscles it stands for.
    var mapStates: [Muscle: MuscleState] {
        var out: [Muscle: MuscleState] = [:]
        for row in rows where row.state != .noData {
            guard let shape = MuscleBodyGeometry.mapShape(for: row.muscle) else { continue }
            if let cur = out[shape], cur <= row.state { continue }
            out[shape] = row.state
        }
        return out
    }

    func row(_ m: Muscle) -> MuscleRowSummary? { rows.first { $0.muscle == m } }
}

nonisolated enum MusclesSummaryBuilder {
    static let windowDays = MuscleLoad.chronicDays

    /// `calendar` names the user's day (the hub's dates are the device's local day keys).
    static func build(_ input: MusclesInput, calendar: Calendar) -> MusclesSummary {
        let asOfDay = isoDay(input.now, calendar)
        let windowStart = input.now.addingTimeInterval(-Double(windowDays) * 86_400)
        let sessions = input.sessions.filter { $0.at <= input.now }.sorted { $0.at < $1.at }
        let load = MuscleLoad.compute(MuscleLoad.Inputs(asOf: asOfDay, bodyWeight: input.bodyWeight,
                                                        loggedSessions: sessions.map(\.session)))

        // Per-workout muscle loads = the same maths over one session (its own day as asOf).
        var perSession: [(s: MusclesSession, loads: [String: Double])] = []
        for s in sessions {
            let one = MuscleLoad.compute(MuscleLoad.Inputs(asOf: s.session.date, bodyWeight: input.bodyWeight, loggedSessions: [s.session]))
            var loads: [String: Double] = [:]
            for r in one?.muscles ?? [] where r.acute > 0 { loads[r.muscle] = r.acute }
            perSession.append((s, loads))
        }
        // Calibration window = the chronic window (28 d): an old session cannot fake a fresh state.
        let recent = perSession.filter { $0.s.at >= windowStart }
        let workouts = recent.enumerated().map { i, x in MuscleFreshness.Workout(id: "\(i)", at: x.s.at, loads: x.loads) }
        let fresh = MuscleFreshness.compute(workouts: workouts, asOf: input.now)

        let acuteStart = isoDay(input.now.addingTimeInterval(-Double(MuscleLoad.acuteDays - 1) * 86_400), calendar)
        let shown = Muscle.allCases.filter { m in
            MuscleBodyGeometry.mapMuscles.contains(m) || (fresh.row(m)?.workouts ?? 0) > 0
        }
        var rows: [MuscleRowSummary] = shown.map { m in
            let f = fresh.row(m)
            let l = load?.row(m)
            let n = f?.workouts ?? 0
            let state: MuscleState
            switch f?.status {
            case .recovered?: state = .recovered
            case .fatigued?: state = .fatigued
            case .depleted?: state = .depleted
            default: state = n > 0 ? .calibrating(n) : .noData
            }
            let lastName = recent.last(where: { ($0.loads[m.rawValue] ?? 0) > 0 })?.s.name
            let counted = countedSets(m, sessions: sessions, from: acuteStart, bodyWeight: input.bodyWeight)
            return MuscleRowSummary(
                muscle: m, state: state, workouts: n, lastAt: f?.lastAt, hoursSince: f?.hoursSince,
                lastSessionName: lastName, lastLoad: f?.lastLoad, medianLoad: f?.medianLoad,
                aboveP75: { if let a = f?.lastLoad, let p = f?.p75Load { return a > p } else { return false } }(),
                recoveryHours: f?.recoveryHours,
                acute: l?.acute ?? 0, chronic: l?.chronic ?? 0, ratio: l?.ratio, band: l?.band, counted: counted)
        }
        let order = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
        let displayOrder = Dictionary(uniqueKeysWithValues: MuscleBodyGeometry.mapMuscles.enumerated().map { ($1, $0) })
        rows.sort { a, b in
            if a.state.rank != b.state.rank { return a.state.rank < b.state.rank }
            if (a.ratio ?? -1) != (b.ratio ?? -1) { return (a.ratio ?? -1) > (b.ratio ?? -1) }
            if a.workouts != b.workouts { return a.workouts > b.workouts }
            return (displayOrder[a.muscle] ?? 100 + order[a.muscle]!) < (displayOrder[b.muscle] ?? 100 + order[b.muscle]!)
        }
        let trained = rows.contains { $0.workouts > 0 }
        let settled = rows.contains { [.depleted, .fatigued, .recovered].contains($0.state) }
        let last = sessions.last(where: { s in s.session.sets.contains { ($0.reps ?? 0) > 0 || ($0.durationS ?? 0) > 0 } })
        return MusclesSummary(phase: settled ? .populated : (trained ? .calibrating : .empty), rows: rows,
                              lastSessionName: last?.name, lastSessionAt: last?.at, asOf: input.now)
    }

    /// The 7-day sets that credited `muscle`, per exercise (reps × kg × weight; bodyweight sets use
    /// the same 0.65 × body weight as `MuscleLoad`, skipped without a weigh-in).
    static func countedSets(_ muscle: Muscle, sessions: [MusclesSession], from: String,
                            bodyWeight: [MuscleLoad.BodyWeight]) -> [MuscleCounted] {
        var byExercise: [String: MuscleCounted] = [:]
        var order: [String] = []
        let bw = bodyWeight.compactMap(\.weightKg).last
        for s in sessions {
            guard String(s.session.date.prefix(10)) >= from else { continue }
            for x in s.session.sets {
                guard let key = x.exerciseKey, let w = MuscleMap.weights(forExercise: key)?.first(where: { $0.muscle == muscle })?.weight,
                      let reps = x.reps, reps > 0 else { continue }
                let kg = (x.weightKg ?? 0) > 0 ? x.weightKg! : bw.map { $0 * MuscleLoad.bodyweightCoef }
                guard let kg else { continue }
                let name = MuscleMap.catalogueKey(key) ?? key
                if byExercise[name] == nil { order.append(name); byExercise[name] = MuscleCounted(exercise: name, weight: w, sets: 0, load: 0) }
                byExercise[name]!.sets += 1
                byExercise[name]!.load += Double(reps) * kg * w
            }
        }
        return order.compactMap { byExercise[$0] }.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.load > $1.load }
    }

    static func isoDay(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

nonisolated func musclesNumber(_ v: Double, _ decimals: Int) -> String { String(format: "%.\(decimals)f", v) }
