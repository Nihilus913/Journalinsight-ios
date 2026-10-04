import Foundation
import Observation
import JICore
import JICompute
import JIPersistence

/// B-89 BP-6a — personal records + e1RM per lift. Cache first (the phone's own
/// `StrengthSessionLogStore`, B-52), then the hub's Garmin history (`GET /training/strength-records`,
/// the one-time backfill source); the records are always computed here with `OneRepMax` (B-50).
@Observable @MainActor
public final class StrengthRecordsViewModel {
    public private(set) var lifts: [OneRepMax.LiftHistory] = []
    public private(set) var hubError: String?
    public private(set) var loading = false
    public private(set) var hasGarmin = false
    public var selected: String?

    private let store: StrengthSessionLogStore?
    private let provider: (any TrainingProviding)?
    private let today: () -> String
    private var hub: StrengthRecordsOut?

    public init(store: StrengthSessionLogStore?, provider: (any TrainingProviding)?, today: @escaping () -> String) {
        self.store = store; self.provider = provider; self.today = today
    }

    public var selectedLift: OneRepMax.LiftHistory? { lifts.first { $0.lift == selected } ?? lifts.first }

    public func load() async {
        recompute()
        guard let provider else { return }
        loading = hub == nil
        do {
            hub = try await provider.strengthRecords()
            hubError = nil
        } catch is StrengthRecordsUnavailable {
            hubError = nil
        } catch {
            hubError = StrengthOutbox.describe(error)
        }
        loading = false
        recompute()
    }

    /// Plan name of a logged exercise key ("barbell bench press" → "Barbell Bench Press"), nil when
    /// it is not one of the plan lifts.
    nonisolated static func planLift(_ key: String) -> String? {
        let n = Progression.normalizedName(key)
        return ExerciseAliases.byPlanName.keys.first { Progression.normalizedName($0) == n }
    }

    func recompute() {
        var inputs: [OneRepMax.Input] = []
        var hubLogged = Set<String>()
        for l in hub?.lifts ?? [] {
            for s in l.sessions {
                if s.sources?.contains("logged") == true { hubLogged.insert("\(l.lift)|\(s.date)") }
                for x in s.sets {
                    inputs.append(.init(lift: l.lift, date: s.date, reps: x.reps, weightKg: x.weightKg,
                                        source: s.sources?.contains("garmin") == true ? "garmin" : "logged"))
                }
            }
        }
        if let store {
            let to = today()
            let from = (try? CalendarMath.addDays(to, -3650)) ?? "2000-01-01"
            for s in (try? store.sessions(from: from, to: to)) ?? [] {
                for x in (try? store.sets(sessionClientId: s.clientId)) ?? [] where x.kind == .reps {
                    guard let lift = Self.planLift(x.exerciseKey), !hubLogged.contains("\(lift)|\(s.date)") else { continue }
                    inputs.append(.init(lift: lift, date: s.date, reps: x.reps, weightKg: x.weightKg, source: "logged"))
                }
            }
        }
        lifts = OneRepMax.histories(inputs).sorted { ($0.sessions.count, $1.lift) > ($1.sessions.count, $0.lift) }
        hasGarmin = lifts.contains { $0.sessions.contains { $0.sources.contains("garmin") } }
    }

    /// Fixture seam for tests / previews.
    func setHub(_ out: StrengthRecordsOut) { hub = out; recompute() }
}

extension StrengthRecordsViewModel: Hashable {
    public nonisolated static func == (a: StrengthRecordsViewModel, b: StrengthRecordsViewModel) -> Bool { a === b }
    public nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
