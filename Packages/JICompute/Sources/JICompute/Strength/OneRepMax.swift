import Foundation

/// B-89 / BP-6a — strength personal records + estimated 1RM per lift. Pure twin of HT
/// `app/training/strength_records.py` (card docs/waves/cards/2610-b89.md):
/// Epley `w·(1 + r/30)` (r = 1 → w), reps 1…12, weight ≥ 20 kg barbell / 4 kg dumbbell,
/// session = lift × day (best-set e1RM, heaviest, volume Σ reps·kg), PR = strictly greater
/// than every earlier session (a tie is not a record).
public nonisolated enum OneRepMax {
    public static let maxReps = 12
    public static let minKgBarbell = 20.0
    public static let minKgDumbbell = 4.0

    public struct LiftSet: Sendable, Equatable, Hashable {
        public let reps: Int, weightKg: Double
        public init(reps: Int, weightKg: Double) { self.reps = reps; self.weightKg = weightKg }
    }

    public enum RecordKind: String, Sendable, Equatable, CaseIterable { case e1rm, heaviest, volume }

    public struct Session: Sendable, Equatable, Identifiable {
        public let date: String
        public let sets: [LiftSet]
        public let e1rm: Double, heaviestKg: Double, volumeKg: Double
        public let prs: [RecordKind]
        public let sources: Set<String>
        public var id: String { date }
        public var topSet: LiftSet { sets.max { (OneRepMax.epley($0), $0.weightKg) < (OneRepMax.epley($1), $1.weightKg) }! }
        public var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    }

    public struct Record: Sendable, Equatable {
        public let value: Double, date: String
        public let set: LiftSet?
        public let reps: Int?
    }

    public struct Records: Sendable, Equatable {
        public var bestE1rm: Record?, heaviest: Record?, bestVolume: Record?
    }

    public enum Status: Sendable, Equatable {
        case none, first, newBest, held, down(percent: Int)
    }

    public struct LiftHistory: Sendable, Equatable, Identifiable {
        public let lift: String
        public let perHand: Bool
        /// Newest first.
        public let sessions: [Session]
        public let records: Records
        public var id: String { lift }
        public var latest: Session? { sessions.first }
    }

    public static func epley(_ s: LiftSet) -> Double { epley(weightKg: s.weightKg, reps: s.reps) }
    public static func epley(weightKg: Double, reps: Int) -> Double {
        reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    public static func isDumbbell(_ lift: String) -> Bool { lift.hasPrefix("DB ") || lift.hasPrefix("KB ") }
    public static func minKg(_ lift: String) -> Double { isDumbbell(lift) ? minKgDumbbell : minKgBarbell }

    public static func counts(lift: String, reps: Int?, weightKg: Double?) -> Bool {
        guard let reps, let weightKg else { return false }
        return (1...maxReps).contains(reps) && weightKg >= minKg(lift)
    }

    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /// One input set: lift = plan name, date = "YYYY-MM-DD", source = "garmin" | "logged".
    public struct Input: Sendable, Equatable {
        public let lift: String, date: String, reps: Int?, weightKg: Double?, source: String
        public init(lift: String, date: String, reps: Int?, weightKg: Double?, source: String) {
            self.lift = lift; self.date = date; self.reps = reps; self.weightKg = weightKg; self.source = source
        }
    }

    /// Per lift (sorted by name) its sessions newest first + records.
    public static func histories(_ inputs: [Input]) -> [LiftHistory] {
        var byLift: [String: [String: [LiftSet]]] = [:]
        var sources: [String: Set<String>] = [:]
        for i in inputs where counts(lift: i.lift, reps: i.reps, weightKg: i.weightKg) {
            byLift[i.lift, default: [:]][i.date, default: []].append(LiftSet(reps: i.reps!, weightKg: i.weightKg!))
            sources["\(i.lift)|\(i.date)", default: []].insert(i.source)
        }
        return byLift.keys.sorted().map { lift in
            var best = (e1rm: 0.0, heavy: 0.0, vol: 0.0)
            var rec = Records()
            var sessions: [Session] = []
            for date in byLift[lift]!.keys.sorted() {
                let sets = byLift[lift]![date]!
                let top = sets.max { (epley($0), $0.weightKg) < (epley($1), $1.weightKg) }!
                let e1 = round1(epley(top)), heavy = sets.map(\.weightKg).max()!
                let vol = round1(sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg })
                var prs: [RecordKind] = []
                if e1 > best.e1rm { prs.append(.e1rm); best.e1rm = e1; rec.bestE1rm = Record(value: e1, date: date, set: top, reps: nil) }
                if heavy > best.heavy { prs.append(.heaviest); best.heavy = heavy; rec.heaviest = Record(value: heavy, date: date, set: nil, reps: nil) }
                if vol > best.vol {
                    prs.append(.volume); best.vol = vol
                    rec.bestVolume = Record(value: vol, date: date, set: nil, reps: sets.reduce(0) { $0 + $1.reps })
                }
                sessions.append(Session(date: date, sets: sets, e1rm: e1, heaviestKg: heavy, volumeKg: vol, prs: prs,
                                        sources: sources["\(lift)|\(date)"] ?? []))
            }
            return LiftHistory(lift: lift, perHand: isDumbbell(lift), sessions: sessions.reversed(), records: rec)
        }
    }

    /// Latest session vs the best e1RM of the sessions in the 28 days before it: a PR is
    /// "new best", ≥ 95 % "held", else "down N %". One session → first; none earlier in 4 weeks →
    /// compared with the all-time best before it.
    public static func status(_ h: LiftHistory) -> Status {
        guard let latest = h.latest else { return .none }
        let earlier = Array(h.sessions.dropFirst())
        guard !earlier.isEmpty else { return .first }
        if latest.prs.contains(.e1rm) { return .newBest }
        let cutoff = shift(latest.date, days: -28)
        let window = earlier.filter { $0.date >= cutoff }
        let ref = (window.isEmpty ? earlier : window).map(\.e1rm).max() ?? latest.e1rm
        guard ref > 0, latest.e1rm < ref * 0.95 else { return .held }
        return .down(percent: Int(((1 - latest.e1rm / ref) * 100).rounded()))
    }

    static func shift(_ iso: String, days: Int) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso), let s = cal.date(byAdding: .day, value: days, to: d) else { return iso }
        return f.string(from: s)
    }
}
