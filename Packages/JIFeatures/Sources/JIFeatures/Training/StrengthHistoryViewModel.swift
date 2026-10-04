import Foundation
import Observation
import JICore
import JICompute
import JIPersistence

/// W-B38-A A-11 — logged strength sessions by date → sets. Cache first (the phone's own
/// `StrengthSessionLogStore`, so History renders offline), then the hub's
/// `GET /strength-sessions?from&to`, merged into the store on client ids (never doubles a row the
/// phone sent itself, never drops a local row the hub has not received yet).
@Observable @MainActor
public final class StrengthHistoryViewModel {
    public struct Exercise: Identifiable, Equatable {
        public let key: String
        public let sets: [StrengthSetLog]
        public var id: String { key }
        /// Heaviest weight lifted, nil when none of the sets carried one.
        public var topKg: Double? { sets.compactMap(\.weightKg).max() }
    }

    public struct Entry: Identifiable, Equatable {
        public let session: StrengthSessionLog
        public let exercises: [Exercise]
        public var id: String { session.clientId }
        public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var hubError: String?
    public private(set) var loadedFromHub = false

    private let store: StrengthSessionLogStore
    private let provider: (any TrainingProviding)?
    private let today: () -> String
    private let days: Int

    public init(store: StrengthSessionLogStore, provider: (any TrainingProviding)?, today: @escaping () -> String, days: Int = 90) {
        self.store = store; self.provider = provider; self.today = today; self.days = days
    }

    private var range: (from: String, to: String) {
        let to = today()
        return ((try? CalendarMath.addDays(to, -days)) ?? to, to)
    }

    /// B-89: the Records screen over the same store, hub and day.
    public func makeRecords() -> StrengthRecordsViewModel {
        StrengthRecordsViewModel(store: store, provider: provider, today: today)
    }

    public func load() async {
        readCache()
        guard let provider else { return }
        do {
            let hub = try await provider.strengthSessions(from: range.from, to: range.to)
            try store.mergeFromHub(hub.compactMap(Self.local))
            hubError = nil
            loadedFromHub = true
        } catch {
            hubError = StrengthOutbox.describe(error)
        }
        readCache()
    }

    public func readCache() {
        let sessions = (try? store.sessions(from: range.from, to: range.to)) ?? []
        entries = sessions.compactMap { s in
            let sets = (try? store.sets(sessionClientId: s.clientId)) ?? []
            guard !sets.isEmpty else { return nil }   // an opened, never-logged session is not history
            var order: [String] = []
            for x in sets where !order.contains(x.exerciseKey) { order.append(x.exerciseKey) }
            return Entry(session: s, exercises: order.map { k in Exercise(key: k, sets: sets.filter { $0.exerciseKey == k }) })
        }
    }

    /// A hub session (and its sets) as local rows; nil when the hub row has no client id to key on.
    nonisolated static func local(_ s: StrengthSessionOut) -> (session: StrengthSessionLog, sets: [StrengthSetLog])? {
        guard let cid = s.clientId?.lowercased(), let date = s.date else { return nil }
        let session = StrengthSessionLog(clientId: cid, remoteId: s.sessionLogId, sessionId: s.sessionId, date: String(date.prefix(10)),
                                         startedAt: s.startedAt ?? date, endedAt: s.endedAt,
                                         hkWorkoutUuid: s.hkWorkoutUuid?.lowercased())
        let sets = (s.sets ?? []).compactMap { x -> StrengthSetLog? in
            guard let xid = x.clientId?.lowercased() else { return nil }
            return StrengthSetLog(clientId: xid, sessionClientId: cid, exerciseKey: x.exerciseKey, exerciseId: x.exerciseId,
                                  setIndex: x.setIndex ?? 0, kind: x.kind == "timed" ? .timed : .reps, reps: x.reps,
                                  weightKg: x.weightKg, durationS: x.durationS, rpe: x.rpe, performedAt: x.performedAt ?? session.startedAt)
        }
        return (session, sets)
    }
}
