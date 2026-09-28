import Foundation
import JICore

/// W-TGT (spec §3, §5) — the phone's ONE targets document, PrefStore `targets.v1`. Goals and
/// Limits are never seeded; Rules are nil until changed. `migrateIfNeeded` imports today's stores
/// once (flag `targets.migrated.v1`), verbatim, and queues one mirror body (outbox kind
/// `targets`) — only when the import holds a goal (W-FIX8 T-1). The old keys stay readable until that body is delivered, then go
/// (`finishMigrationIfDelivered`). Rollback = the old keys.
public nonisolated struct TargetsStore: Sendable {
    public static let key = "targets.v1"
    public static let migrationKey = "targets.migrated.v1"

    /// The stores the import reads (spec §1). Spelled here because their owners live in
    /// JIFeatures; `TargetsKeysTests` (JIFeatures) pins them to those owners.
    public static let gateSettingsKey = "gate.settings"
    public static let morningOverridesKey = "config_overrides.morning_gate"
    public static let kpiRuleOverridesKey = "config_overrides.kpi_rules"
    public static let kpiTargetsCacheKey = "kpi.targets"
    /// Removed once the first mirror is delivered. `kpi.targets` is an OfflineCache entry (the
    /// hub's rows), not a store, so it stays.
    public static let legacyKeys = [MacroGoalsStore.key, gateSettingsKey, morningOverridesKey, kpiRuleOverridesKey]

    public enum MigrationState: String, Codable, Sendable { case imported, delivered }

    /// Where the import reads the hub-owned caches and queues the mirror body.
    public struct Sources: Sendable {
        public var cache: OfflineCache?
        public var goals: GoalStore?
        public var outbox: Outbox?
        public init(cache: OfflineCache?, goals: GoalStore?, outbox: Outbox?) {
            self.cache = cache; self.goals = goals; self.outbox = outbox
        }
    }

    private let prefs: PrefStore
    public init(prefs: PrefStore) { self.prefs = prefs }

    /// The stored document, or nil before the import (or when unreadable).
    public func loadIfPresent() -> TargetsDocument? {
        (try? loadThrowing()) ?? nil
    }

    /// Throws on a row that exists but does not decode (never silently reset).
    public func loadThrowing() throws -> TargetsDocument? {
        try prefs.get(Self.key, as: TargetsDocument.self)
    }

    /// The document; `.empty` (no numbers) before the import.
    public func load() -> TargetsDocument { loadIfPresent() ?? .empty }

    /// The one-shot `clearAllGoals` intent belongs to a queued mirror body, never to `targets.v1`.
    public func save(_ document: TargetsDocument) throws {
        var d = document
        d.clearAllGoals = false
        try prefs.set(Self.key, d)
    }

    // MARK: W-FIX8 T-1 — hub wins over an empty local document

    /// One-time repair flag (W-FIX8 T-1): set once the launch has compared this phone's goals with
    /// the hub's. The 2026-09-28 P0 left a phone whose document has no goals while the hub holds
    /// them again (restored); the next launch reads the hub once and adopts them.
    public static let hubSeedKey = "targets.hubSeeded.v1"

    /// The launch should read the hub's document: never done on this install AND this phone has
    /// no goal (a phone that holds goals is the source of truth and needs nothing).
    public var needsHubSeed: Bool {
        guard ((try? prefs.get(Self.hubSeedKey, as: Bool.self)) ?? nil) != true else { return false }
        return loadIfPresent()?.goals.isEmpty ?? true
    }

    public func markHubSeeded() { try? prefs.set(Self.hubSeedKey, true) }

    /// Takes the hub's sections this phone has nothing in (`TargetsDocument.adoptingHub`) and saves
    /// locally — no mirror body (the hub already holds these numbers). Returns the stored document.
    @discardableResult
    public func adoptHub(_ server: TargetsDocument, log: (String) -> Void = { _ in }) -> TargetsDocument {
        let local = load()
        let next = local.adoptingHub(server)
        guard next != local else { return local }
        do { try save(next) } catch { log("targets: adopting the hub's document failed \(error)"); return local }
        if local.goals.isEmpty && !next.goals.isEmpty { log("targets: adopted the hub's goals (this phone had none)") }
        return next
    }

    public var migrationState: MigrationState? {
        (try? prefs.get(Self.migrationKey, as: MigrationState.self)) ?? nil
    }

    /// Spec §5: runs once. Reads every old store, builds the document (no value changes, missing =
    /// nil), saves it, queues one `PUT /planning/targets` body. Returns nil when already done.
    @discardableResult
    public func migrateIfNeeded(_ sources: Sources, log: (String) -> Void = { _ in }) -> TargetsImportResult? {
        guard migrationState == nil else { return nil }
        let result = TargetsImporter.makeDocument(from: legacySources(sources))
        // A document that already exists (restored backup) wins over a re-import.
        let document = loadIfPresent() ?? result.document
        do { try save(document) } catch { log("targets import: save failed \(error)"); return nil }
        result.discarded.forEach { log("targets import discarded: \($0)") }
        // W-FIX8 T-1 (P0 2026-09-28 14:51): an import with NO goals (fresh install, empty caches)
        // is never mirrored — that body wiped the hub's goals. The launch reads the hub instead
        // (`needsHubSeed` / `adoptHub`); the next edit mirrors the whole document.
        if document.goals.isEmpty {
            log("targets import: no goals on this phone — not mirrored; the hub's are read at launch")
        } else {
            _ = try? sources.outbox?.enqueue(kind: TargetsDocument.outboxKind, payload: document)
        }
        try? prefs.set(Self.migrationKey, MigrationState.imported)
        return TargetsImportResult(document: document, discarded: result.discarded)
    }

    /// Spec §5.6: after the first mirror is delivered (no `targets` row pending), the old keys go.
    /// Returns true only on the call that finished the migration.
    @discardableResult
    public func finishMigrationIfDelivered(outbox: Outbox) -> Bool {
        guard migrationState == .imported, let pending = try? outbox.pending(),
              !pending.contains(where: { $0.kind == TargetsDocument.outboxKind }) else { return false }
        for key in Self.legacyKeys { try? prefs.remove(key) }
        try? prefs.set(Self.migrationKey, MigrationState.delivered)
        return true
    }

    func legacySources(_ s: Sources) -> TargetsLegacySources {
        TargetsLegacySources(
            macros: get(MacroGoalsStore.key, MacroGoals.self),
            gateSettings: get(Self.gateSettingsKey, LegacyGateSettings.self),
            morningOverrides: get(Self.morningOverridesKey, [String: Double].self),
            kpiRuleOverrides: get(Self.kpiRuleOverridesKey, [String: LegacyKpiRuleOverride].self),
            kpiTargets: ((try? s.cache?.get(Self.kpiTargetsCacheKey, as: [KpiTarget].self)) ?? nil)?.value,
            hubGoals: (try? s.goals?.loadGoalTargetsMirror()) ?? nil
        )
    }

    private func get<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        (try? prefs.get(key, as: T.self)) ?? nil
    }
}
