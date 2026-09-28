import Foundation
import JICore

/// W-TGT (spec §3, §5) — the phone's ONE targets document, PrefStore `targets.v1`. Goals and
/// Limits are never seeded; Rules are nil until changed. `migrateIfNeeded` imports today's stores
/// once (flag `targets.migrated.v1`), verbatim, and queues one mirror body (outbox kind
/// `targets`). The old keys stay readable until that body is delivered, then go
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

    public func save(_ document: TargetsDocument) throws { try prefs.set(Self.key, document) }

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
        _ = try? sources.outbox?.enqueue(kind: TargetsDocument.outboxKind, payload: document)
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
