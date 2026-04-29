// JournalInsight/Storage/SchemaVersions.swift
import Foundation
import SwiftData

/// V0 — pre-encryption schema. Captures the JournalEntry shape that ships
/// in production today: plaintext `text`, `moodRaw`, and a `Tag` relationship.
/// SwiftData uses this only to *describe* the on-disk format that Stage 1
/// migrates *from*. Code that reads V0 rows works through the V1 model
/// (whose properties happen to be a superset, with nullable plaintext).
enum JournalSchemaV0: VersionedSchema {
    static let versionIdentifier = Schema.Version(0, 0, 0)
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Goal.self, Tag.self]
    }
}

/// V1 — adds `bodyCipher`, `nonce`, `schemaVersion` columns to `JournalEntry`,
/// drops `@Attribute(.unique)` from `Tag.name`, and makes `text` / `moodRaw` optional.
/// V1 still includes the `Tag` model so Stage 2 migration can read legacy data.
/// V1.1 cleanup migration (out of scope here) will drop legacy columns + Tag entity.
enum JournalSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Goal.self, Tag.self]
    }
}

/// Lightweight migration — SwiftData handles the column adds automatically
/// because every new column has a default value (`Data()`, `Data()`, `0`).
/// The unique-constraint drop on `Tag.name` is also handled lightweightly.
enum JournalMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        JournalSchemaV0.self,
        JournalSchemaV1.self
    ]
    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: JournalSchemaV0.self, toVersion: JournalSchemaV1.self)
    ]
}
