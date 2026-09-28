import Foundation
import JICore
import JIPersistence

/// W-B40 L2 (B-40b-2, spec §10.4 / B-52): one queued template write. `localId` names a template
/// that exists only on this phone so far (a create the hub has not answered); `templateId` is
/// the hub's id for update/delete.
public nonisolated struct WorkoutTemplateWrite: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable { case create, update, delete }
    public var op: Op
    public var templateId: Int?
    public var localId: String?
    public var draft: WorkoutTemplateDraft?

    public static func create(_ draft: WorkoutTemplateDraft, localId: String = UUID().uuidString) -> Self {
        Self(op: .create, templateId: nil, localId: localId, draft: draft)
    }
    public static func update(_ id: Int, _ draft: WorkoutTemplateDraft) -> Self { Self(op: .update, templateId: id, localId: nil, draft: draft) }
    public static func delete(_ id: Int) -> Self { Self(op: .delete, templateId: id, localId: nil, draft: nil) }
    /// Edit / delete of a template that only exists on this phone (its create is still queued).
    public static func updateLocal(_ localId: String, _ draft: WorkoutTemplateDraft) -> Self { Self(op: .update, templateId: nil, localId: localId, draft: draft) }
    public static func deleteLocal(_ localId: String) -> Self { Self(op: .delete, templateId: nil, localId: localId, draft: nil) }
}

/// What one queued row became on this drain pass.
public nonisolated enum WorkoutWriteOutcome: Sendable, Equatable {
    case delivered(WorkoutTemplate?)
    /// Still queued (hub unreachable) — the hub's / the network's own text.
    case queued(String)
    /// The hub (or the X-1 guard) refused THIS row: retired, never retried.
    case refused(String)
}

/// The library's own lane of the durable `Outbox` (kind `"workout_template"`). Every template
/// write from the app is enqueued here BEFORE the hub is asked (offline-first, B-52); the library
/// drains it in-tap and on every load. Pending rows are coalesced per template so an offline
/// editing session replays as ONE write per template, never an old body over a newer one:
/// an update replaces any earlier queued update of the same id; a delete drops queued updates;
/// editing a not-yet-created template rewrites its queued create; deleting it drops the create.
///
/// Rows of this kind are left untouched by the app-wide `OutboxDrainer` (it skips kinds it does
/// not know — never dropped), so this type is the one owner that replays them.
@MainActor
public final class WorkoutLibraryOutbox {
    public nonisolated static let kind = "workout_template"

    private let outbox: Outbox
    private let provider: any WorkoutLibraryProviding
    private var inFlight: Task<[Int64: WorkoutWriteOutcome], Never>?

    public init(outbox: Outbox, provider: any WorkoutLibraryProviding) {
        self.outbox = outbox; self.provider = provider
    }

    /// Queued template writes, oldest first.
    public func pending() -> [(row: Int64, write: WorkoutTemplateWrite)] {
        ((try? outbox.pending()) ?? []).compactMap { row in
            guard row.kind == Self.kind, let w = try? JSONDecoder().decode(WorkoutTemplateWrite.self, from: row.payload) else { return nil }
            return (row.id, w)
        }
    }

    /// Enqueue with coalescing; returns the new row id (nil = the queue itself is unwritable).
    @discardableResult
    public func enqueue(_ write: WorkoutTemplateWrite) -> Int64? {
        var write = write
        let queued = pending()
        switch write.op {
        case .create:
            break
        case .update, .delete:
            if let local = write.localId {   // a template that only exists on this phone
                let creates = queued.filter { $0.write.op == .create && $0.write.localId == local }
                for c in creates { try? outbox.markSent(id: c.row) }
                guard write.op == .update, let draft = write.draft else { return creates.first?.row }
                write = .create(draft, localId: local)
            } else {
                for q in queued where q.write.op == .update && q.write.templateId == write.templateId { try? outbox.markSent(id: q.row) }
            }
        }
        return try? outbox.enqueue(kind: Self.kind, payload: write)
    }

    /// One attempt per queued row, oldest first (serialised like `OutboxDrainer.drainOnce`).
    @discardableResult
    public func drainOnce() async -> [Int64: WorkoutWriteOutcome] {
        if let inFlight { return await inFlight.value }
        let pass = Task { @MainActor [self] in
            defer { self.inFlight = nil }
            return await self.drainPass()
        }
        inFlight = pass
        return await pass.value
    }

    private func drainPass() async -> [Int64: WorkoutWriteOutcome] {
        var results: [Int64: WorkoutWriteOutcome] = [:]
        for (row, write) in pending() {
            do {
                switch write.op {
                case .create:
                    guard let draft = write.draft else { throw WorkoutTemplateWouldClear(templateId: nil) }
                    results[row] = .delivered(try await provider.createWorkoutTemplate(draft))
                case .update:
                    guard let id = write.templateId, let draft = write.draft else { throw WorkoutTemplateWouldClear(templateId: write.templateId) }
                    results[row] = .delivered(try await provider.updateWorkoutTemplate(id: id, draft))
                case .delete:
                    guard let id = write.templateId else { throw WorkoutTemplateWouldClear(templateId: nil) }
                    do { try await provider.deleteWorkoutTemplate(id: id) } catch HubError.http(status: 404, _) {}   // already gone
                    results[row] = .delivered(nil)
                }
                try? outbox.markSent(id: row)
            } catch {
                if Self.isRefusal(error) {
                    try? outbox.markSent(id: row)   // retire: it would only be refused again
                    results[row] = .refused(Self.describe(error))
                } else {
                    try? outbox.markFailed(id: row, error: Self.describe(error))
                    results[row] = .queued(Self.describe(error))
                }
            }
        }
        return results
    }

    /// The hub said "no" about THIS row (4xx other than 401), or the X-1 guard refused it.
    public nonisolated static func isRefusal(_ error: Error) -> Bool {
        if error is WorkoutTemplateWouldClear { return true }
        if case .duplicate? = error as? HubError { return true }   // 409 (same name) — decodes as `.duplicate`
        return OutboxDrainer.isPermanentRejection(error)
    }

    public nonisolated static func describe(_ error: Error) -> String {
        if error is WorkoutTemplateWouldClear { return "A workout needs at least one step — nothing was sent." }
        switch error as? HubError {
        case .http(_, let detail) where detail?.isEmpty == false: return detail!
        case .duplicate(let detail) where !detail.isEmpty: return detail
        case .duplicate: return "A workout with this name already exists."
        case .network(let message): return message
        case .unauthorized: return "Hub rejected the token — check Settings › Connection."
        default: return "Couldn't reach the hub — the workout is saved on this phone and stays queued."
        }
    }
}
