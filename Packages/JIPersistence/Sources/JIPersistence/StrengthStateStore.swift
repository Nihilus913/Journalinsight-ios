import Foundation
import JICore

/// One exercise's locally-mirrored lift state (oracle: `StrengthStateEntry` /
/// `strength_state_local` in `mobile/src/data/StrengthStateStore.ts`). `synced` marks a row
/// written while the hub was unreachable — a later sync pass (not this wave) could push it.
public struct StrengthStateEntry: Codable, Sendable, Equatable {
    public var exerciseId: Int
    public var exerciseName: String
    public var currentWeightKg: Double
    public var progressionStepKg: Double
    public var sets: Int?
    public var repsTarget: Int?
    public var updatedAt: String
    public var synced: Bool
    public init(
        exerciseId: Int, exerciseName: String, currentWeightKg: Double, progressionStepKg: Double,
        sets: Int?, repsTarget: Int?, updatedAt: String, synced: Bool
    ) {
        self.exerciseId = exerciseId; self.exerciseName = exerciseName
        self.currentWeightKg = currentWeightKg; self.progressionStepKg = progressionStepKg
        self.sets = sets; self.repsTarget = repsTarget; self.updatedAt = updatedAt; self.synced = synced
    }
}

/// On-device mirror of the hub's `plan.strength_state` table (oracle: `StrengthStateStore.ts` /
/// `updateExerciseLocalFirst`). Backed by App-Group `UserDefaults` (same suite as
/// `HealthKitPermissions`/`HealthKitBackloader` — a single small JSON blob, not GRDB: this is a
/// handful of rows keyed by `exerciseId`, not a query surface) rather than `OfflineCache`'s SQLite
/// table, so `LiftSteppers`' local-first write survives an app relaunch even before any hub
/// round-trip completes.
public final class StrengthStateStore: Sendable {
    // UserDefaults predates Sendable annotation on this SDK but is thread-safe by documented
    // contract — same reasoning as HealthKitPermissions.defaults.
    private nonisolated(unsafe) let defaults: UserDefaults?
    private static let key = "training.strengthState.v1"
    public static let appGroupSuite = "group.toby913.JournalInsight"

    public init(appGroupSuite: String = StrengthStateStore.appGroupSuite) {
        self.defaults = UserDefaults(suiteName: appGroupSuite)
    }

    /// Test seam: inject a `UserDefaults` double directly (mirrors `HealthKitPermissions`'s own
    /// `init(authorizer:defaults:)` seam).
    public init(defaults: UserDefaults?) { self.defaults = defaults }

    private func readAll() -> [Int: StrengthStateEntry] {
        guard let data = defaults?.data(forKey: Self.key),
              let rows = try? JSON.decoder.decode([StrengthStateEntry].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.exerciseId, $0) })
    }

    private func writeAll(_ rows: [Int: StrengthStateEntry]) {
        guard let data = try? JSON.encoder.encode(Array(rows.values)) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    /// Upserts one exercise's local mirror row. `synced` always resets to `false` on a write
    /// through this method — a caller that successfully pushes to the hub afterward should call
    /// `markSynced(_:)` itself (see `updateExerciseLocalFirst` below).
    public func saveLocal(exerciseId: Int, exerciseName: String, patch: ExerciseUpdate, now: Date = Date()) {
        var rows = readAll()
        rows[exerciseId] = StrengthStateEntry(
            exerciseId: exerciseId, exerciseName: exerciseName,
            currentWeightKg: patch.currentWeightKg, progressionStepKg: patch.progressionStepKg,
            sets: patch.sets, repsTarget: patch.repsTarget,
            updatedAt: now.ISO8601Format(), synced: false
        )
        writeAll(rows)
    }

    public func getLocal(exerciseId: Int) -> StrengthStateEntry? { readAll()[exerciseId] }

    /// W-FIX1 BUG-11: mirrors the hub's `plan.strength_state` (`GET /planning/exercises`) so
    /// read-only surfaces (GoalsSetup's "Next working weight") show the hub's weights, offline too.
    /// Rows come in `synced`. An unsynced local edit is kept (the hub has not seen it yet), and an
    /// exercise without a weight (bodyweight, core) is not written, never a made-up 0.
    public func mirrorHub(_ exercises: [Exercise], now: Date = Date()) {
        var rows = readAll()
        for ex in exercises {
            guard let kg = ex.currentWeightKg else { continue }
            if let existing = rows[ex.exerciseId], !existing.synced { continue }
            rows[ex.exerciseId] = StrengthStateEntry(
                exerciseId: ex.exerciseId, exerciseName: ex.exerciseName,
                currentWeightKg: kg, progressionStepKg: ex.progressionStepKg ?? 0,
                sets: ex.sets, repsTarget: ex.repsTarget.flatMap(Int.init),
                updatedAt: now.ISO8601Format(), synced: true
            )
        }
        writeAll(rows)
    }

    /// B-57 W1: every stored exercise, for GoalsSetup's read-only "Next working weight".
    public func entries() -> [StrengthStateEntry] { readAll().values.sorted { $0.exerciseName < $1.exerciseName } }

    /// Rows written locally that haven't been confirmed pushed to the hub yet.
    public func listUnsynced() -> [StrengthStateEntry] { readAll().values.filter { !$0.synced } }

    public func markSynced(exerciseId: Int) {
        var rows = readAll()
        guard var row = rows[exerciseId] else { return }
        row.synced = true
        rows[exerciseId] = row
        writeAll(rows)
    }
}

/// Local-first wrapper around a hub `updateExercise` call (oracle: `updateExerciseLocalFirst` in
/// `StrengthStateStore.ts`) — same `(exerciseId, patch) -> ExerciseUpdateResult` contract as
/// `TrainingProviding.updateExercise`, so a caller can swap this in without its own call site
/// changing. On a `HubError.network` (hub unreachable) the patch is persisted locally instead of
/// being lost; any other rejection (validation, 401, decode) propagates unchanged — only "the hub
/// was unreachable" is a case this local-first path papers over.
public func updateExerciseLocalFirst(
    store: StrengthStateStore,
    exerciseId: Int,
    exerciseName: String,
    patch: ExerciseUpdate,
    hubUpdate: (Int, ExerciseUpdate) async throws -> ExerciseUpdateResult
) async throws -> ExerciseUpdateResult {
    do {
        let result = try await hubUpdate(exerciseId, patch)
        store.saveLocal(exerciseId: exerciseId, exerciseName: exerciseName, patch: patch)
        store.markSynced(exerciseId: exerciseId)
        return result
    } catch HubError.network {
        store.saveLocal(exerciseId: exerciseId, exerciseName: exerciseName, patch: patch)
        return ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
}
