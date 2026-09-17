import Foundation
import GRDB
import JICore

/// Oracle: `mobile/src/goals/GoalStore.ts`. CRUD over the `goals` table (the ad-hoc freeform
/// list) PLUS the `goal_targets_mirror` table (the local-first mirror of the structured
/// `GET`/`PUT /api/v1/planning/goals` document) — two unrelated tables sharing one class, exactly
/// like the RN oracle (see that file's header comment for why). Both tables are created by
/// `Migrations.swift`'s `v3_capture` migration (L0); neither column set is vaulted.

/// `mobile/src/goals/types.ts::Goal`.
public struct Goal: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var title: String
    public var targetDate: String?
    public var progress: Double
    public var createdAt: String
    public init(id: Int64, title: String, targetDate: String?, progress: Double, createdAt: String) {
        self.id = id; self.title = title; self.targetDate = targetDate; self.progress = progress; self.createdAt = createdAt
    }
}

/// `mobile/src/goals/types.ts::NewGoal`.
public struct NewGoal: Sendable, Equatable {
    public var title: String
    public var targetDate: String?
    public var progress: Double
    public init(title: String, targetDate: String? = nil, progress: Double = 0) {
        self.title = title; self.targetDate = targetDate; self.progress = progress
    }
}

/// Mirrors `GoalStore.ts::updateGoal`'s `Partial<NewGoal>`: `nil` (the default) leaves a field
/// unchanged. `targetDate` is double-optional so a caller can distinguish "leave as-is" (`nil`)
/// from "clear it" (`.some(nil)`), the one field RN's `Partial` can set back to null.
public struct GoalPatch: Sendable {
    public var title: String?
    public var targetDate: String??
    public var progress: Double?
    public init(title: String? = nil, targetDate: String?? = nil, progress: Double? = nil) {
        self.title = title; self.targetDate = targetDate; self.progress = progress
    }
}

/// Port of `mobile/src/goals/progress.ts::clampProgress`. NaN -> 0.
public func clampProgress(_ value: Double) -> Double {
    guard !value.isNaN else { return 0 }
    return min(1, max(0, value))
}

/// Port of `mobile/src/goals/progress.ts::goalStatus`. `complete` (progress >= 1) always wins,
/// even past the target date. Otherwise `overdue` requires the target date STRICTLY before
/// `today` (a plain lexicographic compare over yyyy-mm-dd strings, same as the oracle).
public enum GoalStatus: String, Sendable, Equatable { case complete, overdue, onTrack }

public func goalStatus(targetDate: String?, progress: Double, today: String) -> GoalStatus {
    if clampProgress(progress) >= 1 { return .complete }
    if let targetDate, targetDate < today { return .overdue }
    return .onTrack
}

public struct GoalStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    @discardableResult
    public func addGoal(_ n: NewGoal, now: Date = Date()) throws -> Int64 {
        let createdAt = now.ISO8601Format()
        return try db.pool.write { db in
            try db.execute(
                sql: "INSERT INTO goals (title, target_date, progress, created_at) VALUES (?, ?, ?, ?)",
                arguments: [n.title, n.targetDate, clampProgress(n.progress), createdAt]
            )
            return db.lastInsertedRowID
        }
    }

    public func updateGoal(id: Int64, patch: GoalPatch) throws {
        try db.pool.write { db in
            if let title = patch.title {
                try db.execute(sql: "UPDATE goals SET title = ? WHERE id = ?", arguments: [title, id])
            }
            if let targetDate = patch.targetDate {
                try db.execute(sql: "UPDATE goals SET target_date = ? WHERE id = ?", arguments: [targetDate, id])
            }
            if let progress = patch.progress {
                try db.execute(sql: "UPDATE goals SET progress = ? WHERE id = ?", arguments: [clampProgress(progress), id])
            }
        }
    }

    public func setProgress(id: Int64, progress: Double) throws {
        try db.pool.write { db in
            try db.execute(sql: "UPDATE goals SET progress = ? WHERE id = ?", arguments: [clampProgress(progress), id])
        }
    }

    public func deleteGoal(id: Int64) throws {
        try db.pool.write { db in try db.execute(sql: "DELETE FROM goals WHERE id = ?", arguments: [id]) }
    }

    public func listGoals() throws -> [Goal] {
        try db.pool.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, title, target_date, progress, created_at FROM goals ORDER BY created_at DESC, id DESC"
            ).map { row in
                Goal(id: row["id"], title: row["title"], targetDate: row["target_date"], progress: row["progress"], createdAt: row["created_at"])
            }
        }
    }

    // ---- goal_targets_mirror (structured GET/PUT /planning/goals mirror) ----

    /// Upserts the singleton mirror row from a freshly-fetched (or just-PUT) hub `Goals`
    /// document, stamping `synced_at` = now. Call this after every successful read or write so
    /// the mirror never drifts stale relative to what was actually shown.
    public func saveGoalTargetsMirror(_ goals: Goals, now: Date = Date()) throws {
        let syncedAt = now.ISO8601Format()
        let strengthJSON = String(data: (try? JSONEncoder().encode(goals.strength)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        try db.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO goal_targets_mirror
                    (id, weight_base_kg, weight_target_kg, weight_target_date, strength_json, steps_daily, kcal_goal, protein_g, carbs_g, fat_g, synced_at)
                VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    weight_base_kg = excluded.weight_base_kg,
                    weight_target_kg = excluded.weight_target_kg,
                    weight_target_date = excluded.weight_target_date,
                    strength_json = excluded.strength_json,
                    steps_daily = excluded.steps_daily,
                    kcal_goal = excluded.kcal_goal,
                    protein_g = excluded.protein_g,
                    carbs_g = excluded.carbs_g,
                    fat_g = excluded.fat_g,
                    synced_at = excluded.synced_at
                """,
                arguments: [
                    goals.weight.baseKg, goals.weight.targetKg, goals.weight.targetDate, strengthJSON,
                    goals.stepsDaily, goals.nutrition.kcalGoal, goals.nutrition.proteinG, goals.nutrition.carbsG, goals.nutrition.fatG,
                    syncedAt,
                ]
            )
        }
    }

    /// `nil` before the mirror has ever been populated on this device.
    public func loadGoalTargetsMirror() throws -> Goals? {
        try db.pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT weight_base_kg, weight_target_kg, weight_target_date, strength_json, steps_daily, kcal_goal, protein_g, carbs_g, fat_g FROM goal_targets_mirror WHERE id = 1"
            ) else { return nil }
            let strengthJSON: String = row["strength_json"]
            let strength = (try? JSONDecoder().decode([StrengthGoal].self, from: Data(strengthJSON.utf8))) ?? []
            return Goals(
                weight: WeightGoal(baseKg: row["weight_base_kg"], targetKg: row["weight_target_kg"], targetDate: row["weight_target_date"]),
                strength: strength,
                stepsDaily: row["steps_daily"],
                nutrition: NutritionGoal(kcalGoal: row["kcal_goal"], proteinG: row["protein_g"], carbsG: row["carbs_g"], fatG: row["fat_g"])
            )
        }
    }

    /// When the mirror was last refreshed — `nil` if never.
    public func goalTargetsMirrorSyncedAt() throws -> String? {
        try db.pool.read { db in
            try String.fetchOne(db, sql: "SELECT synced_at FROM goal_targets_mirror WHERE id = 1")
        }
    }
}
