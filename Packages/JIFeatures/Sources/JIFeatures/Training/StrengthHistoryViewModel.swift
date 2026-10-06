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
    /// W-FIX-P3 RG-61: a Garmin-recorded strength day (from `GET /training/strength-records`) —
    /// listed under the logged sessions so History never says "none" beside Garmin's sessions.
    public nonisolated struct GarminEntry: Identifiable, Equatable, Sendable {
        public struct Lift: Equatable, Sendable { public let lift: String; public let line: String }
        public let date: String
        public let lifts: [Lift]
        public var id: String { date }
    }
    public private(set) var garmin: [GarminEntry] = []
    @ObservationIgnored private var records: StrengthRecordsOut?
    public private(set) var hubError: String?
    public private(set) var loadedFromHub = false
    /// B-52 p2: the hub was unreachable and its answer came from the offline read cache (fetched
    /// then). History already renders from the phone's own store; the stale copy is NOT merged
    /// (it could only replay an older hub state over newer local rows) — the screen says offline.
    public private(set) var staleSince: Date?
    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }

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
            let range = self.range
            let (hub, since) = try await HubReadTrace.collect { try await provider.strengthSessions(from: range.from, to: range.to) }
            staleSince = since
            hubError = nil
            if since == nil {
                try store.mergeFromHub(hub.compactMap(Self.local))
                loadedFromHub = true
            }
        } catch {
            hubError = StrengthOutbox.describe(error)
        }
        // W-FIX-P3 RG-61: Garmin's strength days (the hub's records history); none on an older hub.
        records = try? await provider.strengthRecords()
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
        garmin = records.map { Self.garminEntries($0, excludingDates: Set(entries.map(\.session.date))) } ?? []
    }

    /// W-FIX-P3 RG-61: Garmin-sourced record sessions grouped by day (newest first), lifts by name;
    /// a day the phone already lists as a logged session is left out (never shown twice).
    nonisolated static func garminEntries(_ out: StrengthRecordsOut, excludingDates: Set<String>) -> [GarminEntry] {
        var byDate: [String: [GarminEntry.Lift]] = [:]
        for l in out.lifts.sorted(by: { $0.lift < $1.lift }) {
            for s in l.sessions where s.sources?.contains("garmin") == true {
                let day = String(s.date.prefix(10))
                guard !excludingDates.contains(day) else { continue }
                let line: String = s.sets.map { (x: StrengthRecordSetOut) -> String in
                    let r: String = x.reps.map { String($0) } ?? "—"
                    guard let kg = x.weightKg else { return r + " reps" }
                    return StrengthFormat.kg(kg) + " × " + r
                }.joined(separator: "  ·  ")
                byDate[day, default: []].append(.init(lift: l.lift, line: line))
            }
        }
        return byDate.keys.sorted(by: >).map { GarminEntry(date: $0, lifts: byDate[$0] ?? []) }
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
