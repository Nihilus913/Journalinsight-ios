/// W-B38-A A-9 (gap #29): what the next set's weight / reps fields are prefilled with.
/// Priority per field: the last set of THIS exercise in THIS session → the plan's target
/// (`ProgressionService` nextKg + rep target) → the last logged session's last set.
/// A missing or non-positive value stays nil — never a seeded zero (XC rule 5).
public nonisolated enum LastSetDefaults {
    public enum Source: Sendable, Equatable { case thisSession, plan, lastSession, none }

    public struct Value: Sendable, Equatable {
        public let weightKg: Double?
        public let reps: Int?
        /// Where the weight came from (or reps, when no weight is known).
        public let source: Source
        public init(weightKg: Double?, reps: Int?, source: Source) {
            self.weightKg = weightKg; self.reps = reps; self.source = source
        }
    }

    public static func resolve(sessionSets: [LoggedSet], planKg: Double?, planReps: Int?, lastSessionSets: [LoggedSet]) -> Value {
        func latest(_ sets: [LoggedSet]) -> LoggedSet? {
            sets.enumerated().max { a, b in
                let (sa, sb) = (a.element.setNumber ?? Int.min, b.element.setNumber ?? Int.min)
                return sa != sb ? sa < sb : a.offset < b.offset
            }?.element
        }
        func kg(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        func reps(_ v: Int?) -> Int? { v.flatMap { $0 > 0 ? $0 : nil } }

        if let s = latest(sessionSets), kg(s.weightKg) != nil || reps(s.reps) != nil {
            return Value(weightKg: kg(s.weightKg), reps: reps(s.reps), source: .thisSession)
        }
        let last = latest(lastSessionSets)
        let w: (Double?, Source)
        if let p = kg(planKg) { w = (p, .plan) } else if let l = kg(last?.weightKg) { w = (l, .lastSession) } else { w = (nil, .none) }
        let r = reps(planReps) ?? reps(last?.reps)
        var source = w.1
        if source == .none, r != nil { source = reps(planReps) != nil ? .plan : .lastSession }
        return Value(weightKg: w.0, reps: r, source: source)
    }
}
