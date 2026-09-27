/// B-57 W5 — the strength progression rule (B-38 decision, Toby 2026-09-22): when every target
/// set at the current working weight reached the target reps last session, the next working weight
/// is current + one progression step. With auto-suggest off, the target is the last weight lifted.
/// Display-only: it writes nothing (logging and the write-back stay B-38). Not a hub port — no
/// golden fixture; `ParityRegistry` is untouched.
public nonisolated struct LoggedSet: Sendable, Equatable {
    public let exerciseName: String?
    public let category: String?
    public let setNumber: Int?
    public let reps: Int?
    public let weightKg: Double?
    public init(exerciseName: String?, category: String?, setNumber: Int?, reps: Int?, weightKg: Double?) {
        self.exerciseName = exerciseName; self.category = category; self.setNumber = setNumber
        self.reps = reps; self.weightKg = weightKg
    }
}

public nonisolated struct LiftTarget: Sendable, Equatable {
    public let name: String
    public let currentKg: Double
    public let stepKg: Double?
    public let sets: Int?
    public let repsTarget: Int?
    public init(name: String, currentKg: Double, stepKg: Double?, sets: Int?, repsTarget: Int?) {
        self.name = name; self.currentKg = currentKg; self.stepKg = stepKg; self.sets = sets; self.repsTarget = repsTarget
    }
}

public nonisolated enum ProgressionState: Sendable, Equatable {
    case due(nextKg: Double)
    case notYet
    case noSession
    case noTarget
    case manual(lastLiftedKg: Double?)
}

public nonisolated enum Progression {
    public static let weightToleranceKg = 0.01

    /// "BENCH_PRESS" / "Bench  Press " → "bench press".
    public static func normalizedName(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    public static func matches(_ set: LoggedSet, liftName: String) -> Bool {
        let target = normalizedName(liftName)
        guard !target.isEmpty else { return false }
        return [set.exerciseName, set.category].compactMap { $0 }.contains { normalizedName($0) == target }
    }

    public static func evaluate(target: LiftTarget, lastSession: [LoggedSet], autoSuggest: Bool) -> ProgressionState {
        let mine = lastSession.filter { matches($0, liftName: target.name) }
        if !autoSuggest { return .manual(lastLiftedKg: mine.compactMap(\.weightKg).max()) }
        guard let sets = target.sets, sets > 0, let reps = target.repsTarget, reps > 0,
              let step = target.stepKg, step > 0, target.currentKg.isFinite, target.currentKg > 0 else { return .noTarget }
        guard !mine.isEmpty else { return .noSession }
        let working = mine
            .filter { s in s.weightKg.map { abs($0 - target.currentKg) <= weightToleranceKg } ?? false }
            .sorted { ($0.setNumber ?? Int.max) < ($1.setNumber ?? Int.max) }
        guard working.count >= sets else { return .notYet }
        let allHit = working.prefix(sets).allSatisfy { ($0.reps ?? 0) >= reps }
        return allHit ? .due(nextKg: roundKg(target.currentKg + step)) : .notYet
    }

    public static func nextWorkingWeight(target: LiftTarget, state: ProgressionState) -> Double {
        switch state {
        case .due(let next): next
        case .manual(let last): last ?? target.currentKg
        case .notYet, .noSession, .noTarget: target.currentKg
        }
    }

    static func roundKg(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
