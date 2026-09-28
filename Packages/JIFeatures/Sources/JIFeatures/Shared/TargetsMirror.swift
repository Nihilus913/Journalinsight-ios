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

    /// One drain's answer for a row; `keptHub` (W-FIX8 T-1) = a goals-empty body was NOT sent —
    /// the hub holds goals and the phone adopted them (the stored document after adopting).
    private enum DrainOutcome { case push(PushOutcome), keptHub(TargetsDocument) }

    public var hubPending: Bool {
        ((try? outbox.pending()) ?? []).contains { $0.kind == TargetsDocument.outboxKind }
    }

    public var hubStatusText: String? { hubPending ? Self.pendingText : nil }

    /// Saves `document` and mirrors it. `clearAllGoals`: the user removed the last goal on purpose
    /// (W-FIX8 T-1) — only then may a goals-empty body replace the hub's goals.
    @discardableResult
    public func save(_ document: TargetsDocument, clearAllGoals: Bool = false) async -> PushOutcome {
        try? store.save(document)
        var body = document
        body.clearAllGoals = clearAllGoals && document.goals.isEmpty
        guard let id = try? outbox.enqueue(kind: TargetsDocument.outboxKind, payload: body) else { return .queued }
        switch await drain(until: id) {
        case .push(let outcome): return outcome
        case .keptHub(let kept):
            // W-FIX8 T-1: the hub refused a goals-empty body and the phone took the hub's goals.
            // The edit itself (a rule, a limit) still has to reach the hub: mirror the adopted
            // document, which now carries the hub's own goals — never an empty Goals section.
            guard !kept.goals.isEmpty,
                  let again = try? outbox.enqueue(kind: TargetsDocument.outboxKind, payload: kept) else { return .queued }
            if case .push(let outcome) = await drain(until: again) { return outcome }
            return .queued
        }
    }

    /// W-FIX8 T-1 — launch repair, once per install (`TargetsStore.hubSeedKey`), BEFORE the first
    /// push: a phone with no goals reads the hub's document and adopts what it lacks. Never a
    /// PUT. A failed read leaves the flag unset (tried again next launch). Returns true when the
    /// stored document changed.
    @discardableResult
    public static func seedFromHubIfNeeded(store: TargetsStore, hub: (any TargetsProviding)?,
                                           log: (String) -> Void = { _ in }) async -> Bool {
        guard store.needsHubSeed, let hub else { return false }
        guard let server = try? await hub.targets() else { log("targets: hub read failed — seed retried next launch"); return false }
        let before = store.load()
        let after = store.adoptHub(server, log: log)
        store.markHubSeeded()
        return after != before
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
        adoptRefusals(await drainer.drainOnce())
        store.finishMigrationIfDelivered(outbox: outbox)
        return !hubPending
    }

    /// W-FIX8 T-1: a goals-empty body the hub refused (it holds goals) — the phone takes the hub's.
    @discardableResult
    private func adoptRefusals(_ results: [Int64: Result<OutboxDelivery, Error>]) -> TargetsDocument? {
        var adopted: TargetsDocument?
        for case .failure(let refused as TargetsWouldClearGoals) in results.values {
            adopted = store.adoptHub(refused.server)
        }
        return adopted
    }

    /// Launch step (spec §5), run once per launch BEFORE anything reads targets: the pre-W4
    /// install migration first (it may write `gate.settings`), then the one-shot import, which
    /// queues the first mirror (only when it holds a goal), the one-time hub seed (W-FIX8 T-1);
    /// then one delivery attempt.
    public static func migrateAtLaunch(db: AppDatabase, hub: (any Sendable)?, log: (String) -> Void = { _ in }) async {
        let prefs = PrefStore(db: db)
        GateSettingsStore(prefs: prefs).migratePreW4InstallIfNeeded()
        let outbox = Outbox(db: db)
        TargetsStore(prefs: prefs).migrateIfNeeded(
            .init(cache: OfflineCache(db: db), goals: GoalStore(db: db), outbox: outbox), log: log)
        await seedFromHubIfNeeded(store: TargetsStore(prefs: prefs), hub: hub as? any TargetsProviding, log: log)
        let mirror = TargetsMirror(prefs: prefs, outbox: outbox, drainer: hub.map { OutboxDrainer(outbox: outbox, hub: $0) })
        await mirror.pushIfPending()
    }

    private func drain(until id: Int64) async -> DrainOutcome {
        defer { store.finishMigrationIfDelivered(outbox: outbox) }
        guard let drainer else { return .push(.queued) }
        for _ in 0..<2 {
            let results = await drainer.drainOnce()
            if let kept = adoptRefusals(results) { return .keptHub(kept) }
            if case .success(.targets(let server)) = results[id] { return .push(.delivered(server)) }
            guard isPending(id) else { return .push(.delivered(nil)) }
            if results[id] != nil { return .push(.queued) }
        }
        return .push(.queued)
    }

    private func isPending(_ id: Int64) -> Bool {
        (try? outbox.pending())?.contains { $0.id == id } ?? true
    }
}
