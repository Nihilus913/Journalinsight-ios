import Foundation
import JICore
import JIPersistence

/// W-B38-A A-8: one queued strength-log write. `session` is the session's client_id — the hub
/// accepts it as `{id}`, so a set logged offline can be queued before the session's create has
/// ever reached the hub.
public nonisolated struct StrengthWrite: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable { case createSession, logSet, updateSet, deleteSet, complete }
    public var op: Op
    public var session: String
    public var create: StrengthSessionCreate?
    public var set: StrengthSetIn?
    public var setClientId: String?
    public var complete: StrengthSessionComplete?

    public static func createSession(_ body: StrengthSessionCreate) -> Self {
        Self(op: .createSession, session: body.clientId, create: body)
    }
    public static func logSet(session: String, _ body: StrengthSetIn) -> Self {
        Self(op: .logSet, session: session, set: body, setClientId: body.clientId)
    }
    public static func updateSet(session: String, _ body: StrengthSetIn) -> Self {
        Self(op: .updateSet, session: session, set: body, setClientId: body.clientId)
    }
    public static func deleteSet(session: String, clientId: String) -> Self {
        Self(op: .deleteSet, session: session, setClientId: clientId)
    }
    public static func complete(session: String, _ body: StrengthSessionComplete) -> Self {
        Self(op: .complete, session: session, complete: body)
    }

    init(op: Op, session: String, create: StrengthSessionCreate? = nil, set: StrengthSetIn? = nil,
         setClientId: String? = nil, complete: StrengthSessionComplete? = nil) {
        self.op = op; self.session = session; self.create = create; self.set = set
        self.setClientId = setClientId; self.complete = complete
    }
}

public nonisolated enum StrengthWriteOutcome: Sendable, Equatable {
    case delivered
    /// Still queued (hub unreachable / no routes yet) — the hub's / the network's own text.
    case queued(String)
    /// The hub refused THIS row (4xx other than 401, or the X-1 guard): retired, never retried.
    case refused(String)
}

/// W-B38-A A-8 — the strength logger's lane of the durable `Outbox` (kind `"strength"`, pattern
/// `WorkoutLibraryOutbox`). The logger writes the local store FIRST, then enqueues here; the
/// queue drains in order (a set never reaches the hub before its session's create) and STOPS at
/// the first transient failure, so an offline session replays in the order it was logged.
///
/// Coalescing per set client_id: an edit of a set whose log is still queued rewrites that queued
/// log; a delete of a still-queued set drops it (nothing to tell the hub). Re-enqueueing the same
/// log replaces the earlier row — and the hub is idempotent on client_id anyway, so a replay after
/// a crash between "hub answered" and "row retired" still lands one row.
///
/// The app-wide `OutboxDrainer` (watchdog / retry scheduler / BG refresh) triggers this lane's
/// pass when its provider can serve the strength routes; the Log sets screen drains on load and
/// after each write. Both go through `drainOnce()`, serialised process-wide.
@MainActor
public final class StrengthOutbox {
    public nonisolated static let kind = "strength"

    private let outbox: Outbox
    private let provider: any TrainingProviding
    /// Process-wide, not per instance: the Log sets screen and the app-wide `OutboxDrainer` each
    /// hold their own `StrengthOutbox` over the same queue, and two overlapping passes would
    /// otherwise both read a row before either retired it (a double `complete` = a double
    /// progression advance). Each pass re-reads `pending()`, so a waiting pass skips what the
    /// one before it delivered.
    private static var inFlight: Task<[Int64: StrengthWriteOutcome], Never>?

    public init(outbox: Outbox, provider: any TrainingProviding) {
        self.outbox = outbox; self.provider = provider
    }

    public func pending() -> [(row: Int64, write: StrengthWrite)] {
        ((try? outbox.pending()) ?? []).compactMap { row in
            guard row.kind == Self.kind, let w = try? JSONDecoder().decode(StrengthWrite.self, from: row.payload) else { return nil }
            return (row.id, w)
        }
    }

    public var pendingCount: Int { pending().count }

    @discardableResult
    public func enqueue(_ write: StrengthWrite) -> Int64? {
        var write = write
        let queued = pending()
        if let setId = write.setClientId {
            let sameSet = queued.filter { $0.write.setClientId == setId }
            let queuedLog = sameSet.first { $0.write.op == .logSet }
            switch write.op {
            case .logSet:
                for q in sameSet where q.write.op == .logSet || q.write.op == .updateSet { try? outbox.markSent(id: q.row) }
            case .updateSet:
                for q in sameSet where q.write.op == .updateSet || q.write.op == .logSet { try? outbox.markSent(id: q.row) }
                if queuedLog != nil, let body = write.set { write = .logSet(session: write.session, body) }
            case .deleteSet:
                for q in sameSet { try? outbox.markSent(id: q.row) }
                if queuedLog != nil { return nil }   // the hub never saw it: nothing to delete
            case .createSession, .complete:
                break
            }
        }
        return try? outbox.enqueue(kind: Self.kind, payload: write)
    }

    /// One in-order pass; serialised — a caller arriving mid-pass waits for it, then runs its own
    /// pass (so a row it just enqueued is never left behind by a pass that started before it).
    @discardableResult
    public func drainOnce() async -> [Int64: StrengthWriteOutcome] {
        while let running = Self.inFlight { _ = await running.value }
        let pass = Task { @MainActor [self] in
            defer { Self.inFlight = nil }
            return await self.drainPass()
        }
        Self.inFlight = pass
        return await pass.value
    }

    private func drainPass() async -> [Int64: StrengthWriteOutcome] {
        var results: [Int64: StrengthWriteOutcome] = [:]
        for (row, write) in pending() {
            do {
                try await deliver(write)
                try? outbox.markSent(id: row)
                results[row] = .delivered
            } catch {
                if Self.isRefusal(error) {
                    try? outbox.markSent(id: row)
                    results[row] = .refused(Self.describe(error))
                } else {
                    try? outbox.markFailed(id: row, error: Self.describe(error))
                    results[row] = .queued(Self.describe(error))
                    break   // keep the order: nothing after this row goes before it
                }
            }
        }
        return results
    }

    private func deliver(_ w: StrengthWrite) async throws {
        switch w.op {
        case .createSession:
            guard let body = w.create else { throw HubError.http(status: 422, detail: "Empty session create") }
            _ = try await provider.createStrengthSession(body)
        case .logSet:
            guard let body = w.set else { throw HubError.http(status: 422, detail: "Empty set") }
            _ = try await provider.logStrengthSet(session: w.session, body)
        case .updateSet:
            guard let body = w.set, let id = w.setClientId else { throw HubError.http(status: 422, detail: "Empty set edit") }
            _ = try await provider.updateStrengthSet(session: w.session, clientId: id, body)
        case .deleteSet:
            guard let id = w.setClientId else { throw HubError.http(status: 422, detail: "No set to delete") }
            try await provider.deleteStrengthSet(session: w.session, clientId: id)
        case .complete:
            guard let body = w.complete else { throw HubError.http(status: 422, detail: "Empty complete") }
            _ = try await provider.completeStrengthSession(session: w.session, body)
        }
    }

    public nonisolated static func isRefusal(_ error: Error) -> Bool {
        if error is StrengthAdvanceWouldClear { return true }
        return OutboxDrainer.isPermanentRejection(error)
    }

    public nonisolated static func describe(_ error: Error) -> String {
        if error is StrengthAdvanceWouldClear { return "A progression move without a weight was not sent." }
        if error is StrengthLogUnavailable { return "This hub has no strength log yet — kept on the phone." }
        switch error as? HubError {
        case .http(_, let detail) where detail?.isEmpty == false: return detail!
        case .network(let message): return message
        case .unauthorized: return "Hub rejected the token — check Settings › Connection."
        default: return error.localizedDescription
        }
    }
}
