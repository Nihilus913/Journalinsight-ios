import Foundation
import Observation
import JICompute
import JIPersistence

/// B-90 p5 — the Muscles card / screen state. Reads the phone's own strength log (offline, no hub
/// round-trip — the p3/p4 computes run on device). Garmin sets and cardio credit are not on the
/// phone yet, so legs stay "No data" until a leg lift is logged (card open question 2: never guess).
@Observable @MainActor
final class MusclesModel {
    private(set) var summary: MusclesSummary?
    let calendar: Calendar
    private let source: @MainActor () -> MusclesInput

    init(calendar: Calendar = .autoupdatingCurrent, source: @escaping @MainActor () -> MusclesInput) {
        self.calendar = calendar; self.source = source
    }

    func reload() { summary = MusclesSummaryBuilder.build(source(), calendar: calendar) }

    /// The live model over the on-disk strength log (last 35 days, so the 28 d window is complete).
    static func live(store: StrengthSessionLogStore, now: @escaping @MainActor () -> Date = { Date() }) -> MusclesModel {
        let calendar = Calendar.autoupdatingCurrent
        return MusclesModel(calendar: calendar) {
            let t = now()
            let to = MusclesSummaryBuilder.isoDay(t, calendar)
            let from = MusclesSummaryBuilder.isoDay(t.addingTimeInterval(-35 * 86_400), calendar)
            let sessions = ((try? store.sessions(from: from, to: to)) ?? []).enumerated().compactMap { i, s -> MusclesSession? in
                let sets = ((try? store.sets(sessionClientId: s.clientId)) ?? []).map {
                    MuscleLoad.LoggedSet(exerciseKey: $0.exerciseKey, kind: $0.kind.rawValue, reps: $0.reps, weightKg: $0.weightKg,
                                         durationS: $0.durationS.map(Double.init))
                }
                guard !sets.isEmpty else { return nil }   // an opened, never-logged session is not a workout
                let at = musclesParseInstant(s.startedAt) ?? musclesParseInstant(s.date + "T12:00:00Z") ?? t
                return MusclesSession(name: s.sessionName, at: at,
                                      session: MuscleLoad.LoggedSession(id: i, date: s.date, startedAt: s.startedAt, endedAt: s.endedAt, sets: sets))
            }
            return MusclesInput(now: t, sessions: sessions)
        }
    }

    /// DEBUG screenshot fixtures (`-muscles-fixture populated|calibrating|empty`).
    static func fixture(_ kind: MusclesFixture.Kind, now: Date = Date()) -> MusclesModel {
        let calendar = Calendar.autoupdatingCurrent
        return MusclesModel(calendar: calendar) { MusclesFixture.input(kind, now: now, calendar: calendar) }
    }
}

nonisolated func musclesParseInstant(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
    return a.date(from: s) ?? b.date(from: s) ?? b.date(from: s + "Z")
}

/// Toby's real ranges (mockup BP-2-3): Upper A (row, curl, plank) Mon evening, Upper B (bench, DB
/// shoulder press, triceps) Wed morning, an extra shoulder block Wed evening the last two weeks.
nonisolated enum MusclesFixture {
    enum Kind: String, Sendable, CaseIterable { case populated, calibrating, empty }

    static func input(_ kind: Kind, now: Date, calendar: Calendar) -> MusclesInput {
        var sessions: [MusclesSession] = []
        var nextId = 1
        func add(_ name: String, hoursAgo: Double, _ sets: [MuscleLoad.LoggedSet]) {
            let at = now.addingTimeInterval(-hoursAgo * 3600)
            let start = ISO8601DateFormatter().string(from: at)
            let end = ISO8601DateFormatter().string(from: at.addingTimeInterval(55 * 60))
            sessions.append(MusclesSession(name: name, at: at, session: MuscleLoad.LoggedSession(
                id: nextId, date: MusclesSummaryBuilder.isoDay(at, calendar), startedAt: start, endedAt: end, sets: sets)))
            nextId += 1
        }
        func sets(_ key: String, _ n: Int, reps: Int, kg: Double?, kind: String = "reps", durationS: Double? = nil) -> [MuscleLoad.LoggedSet] {
            Array(repeating: MuscleLoad.LoggedSet(exerciseKey: key, kind: kind, reps: kind == "timed" ? nil : reps, weightKg: kg, durationS: durationS), count: n)
        }
        switch kind {
        case .empty:
            break
        case .calibrating:
            add("Upper B", hoursAgo: 14.5, sets("Barbell Bench Press", 3, reps: 8, kg: 52.5) + sets("DB Shoulder Press", 3, reps: 10, kg: 14)
                + sets("KB Overhead Triceps Extension", 3, reps: 12, kg: 12))
        case .populated:
            for week in 0..<5 {
                let w = Double(week) * 168
                add("Upper A", hoursAgo: 62.6 + w, sets("Barbell Row", 3, reps: 8, kg: 52.5) + sets("DB Biceps Curl", 3, reps: 12, kg: 12)
                    + (week < 2 ? sets("Plank", 2, reps: 0, kg: nil, kind: "timed", durationS: 60) : []))
                add("Upper B", hoursAgo: 26 + w, sets("Barbell Bench Press", 3, reps: 8, kg: week == 0 ? 55 : 52.5)
                    + sets("DB Shoulder Press", 3, reps: 10, kg: 14) + sets("KB Overhead Triceps Extension", 3, reps: 12, kg: 12))
                if week < 2 {
                    add("Shoulders", hoursAgo: 14.5 + w, sets("DB Shoulder Press", 4, reps: 10, kg: week == 0 ? 18 : 16))
                }
            }
        }
        return MusclesInput(now: now, sessions: sessions, bodyWeight: [MuscleLoad.BodyWeight(date: "2020-01-01", weightKg: 78)])
    }
}
