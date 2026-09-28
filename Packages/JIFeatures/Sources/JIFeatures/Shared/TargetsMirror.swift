import Foundation
import JICore
import JIPersistence

// TEMP bridge until B-50: the hub's 05:10 run reads the mirrored document.
/// W-TGT (spec §3, §5) — copies the phone's `TargetsDocument` to the hub as ONE body
/// (`PUT /api/v1/planning/targets`, outbox kind `targets`); replaces the three mirrors (goals,
/// gate settings, kpi targets). Local-first: PrefStore `targets.v1` is written and the row is
/// durable before any network call; a failed push stays queued and the outbox retry paths
/// (`OutboxDrainer(hub:)`, which now knows the kind) deliver it later. Last-write-wins: only the
/// newest queued document is sent.
@MainActor
public final class TargetsMirror {
    /// Words for a change that has not reached the hub yet.
    public static let pendingText = "Not on the hub yet"

    public let store: TargetsStore
    private let outbox: Outbox
    private let drainer: OutboxDrainer?

    public init(prefs: PrefStore, outbox: Outbox, drainer: OutboxDrainer?) {
        self.store = TargetsStore(prefs: prefs); self.outbox = outbox; self.drainer = drainer
    }

    /// `delivered` = the hub has it (its answer when this push's own attempt landed; nil when
    /// another drainer retired the row first). `queued` = still in the outbox.
    public enum PushOutcome: Equatable, Sendable {
        case delivered(TargetsDocument?)
        case queued
    }

    public var hubPending: Bool {
        ((try? outbox.pending()) ?? []).contains { $0.kind == TargetsDocument.outboxKind }
    }

    public var hubStatusText: String? { hubPending ? Self.pendingText : nil }

    /// Saves `document` and mirrors it.
    @discardableResult
    public func save(_ document: TargetsDocument) async -> PushOutcome {
        try? store.save(document)
        guard let id = try? outbox.enqueue(kind: TargetsDocument.outboxKind, payload: document) else { return .queued }
        return await drain(until: id)
    }

    /// Edits the stored document in place and mirrors it (the target editor sheet's save).
    @discardableResult
    public func update(_ change: (inout TargetsDocument) -> Void) async -> PushOutcome {
        var d = store.load()
        change(&d)
        return await save(d)
    }

    /// Foreground / reachable-again: sends anything queued, then finishes the §5 migration.
    @discardableResult
    public func pushIfPending() async -> Bool {
        guard let drainer, hubPending else { store.finishMigrationIfDelivered(outbox: outbox); return false }
        await drainer.drainOnce()
        store.finishMigrationIfDelivered(outbox: outbox)
        return !hubPending
    }

    /// Launch step (spec §5), run once per launch BEFORE anything reads targets: the pre-W4
    /// install migration first (it may write `gate.settings`), then the one-shot import, which
    /// queues the first mirror; then one delivery attempt.
    public static func migrateAtLaunch(db: AppDatabase, hub: (any Sendable)?, log: (String) -> Void = { _ in }) async {
        let prefs = PrefStore(db: db)
        GateSettingsStore(prefs: prefs).migratePreW4InstallIfNeeded()
        let outbox = Outbox(db: db)
        TargetsStore(prefs: prefs).migrateIfNeeded(
            .init(cache: OfflineCache(db: db), goals: GoalStore(db: db), outbox: outbox), log: log)
        let mirror = TargetsMirror(prefs: prefs, outbox: outbox, drainer: hub.map { OutboxDrainer(outbox: outbox, hub: $0) })
        await mirror.pushIfPending()
    }

    private func drain(until id: Int64) async -> PushOutcome {
        defer { store.finishMigrationIfDelivered(outbox: outbox) }
        guard let drainer else { return .queued }
        for _ in 0..<2 {
            let results = await drainer.drainOnce()
            if case .success(.targets(let server)) = results[id] { return .delivered(server) }
            guard isPending(id) else { return .delivered(nil) }
            if results[id] != nil { return .queued }
        }
        return .queued
    }

    private func isPending(_ id: Int64) -> Bool {
        (try? outbox.pending())?.contains { $0.id == id } ?? true
    }
}
