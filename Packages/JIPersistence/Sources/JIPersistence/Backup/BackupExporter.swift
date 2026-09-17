import Foundation
import GRDB
import JIVault

/// Reads every W4 (`v3_capture`) table out of `AppDatabase` and builds a
/// `FoldArchive` — mirrors RN `archive.ts`'s `buildBackupArchive` /
/// `serializeBackupArchive`, scoped to the tables this app's schema actually
/// has (see `BackupTables.v1`). A raw `SELECT *` copies vaulted columns'
/// ciphertext through unchanged, same as RN's dump.ts: this reads straight
/// off GRDB, never through a store's decrypt boundary, so the archive never
/// holds plaintext for a column the vault protects.
public enum BackupExporter {
    /// Builds the archive in-memory. `vaultKey` is the caller's already-wrapped
    /// vault key (`FoldWrappedVaultKeyDTO`, produced by wrapping the current
    /// session's raw key under a user-chosen passphrase) — `nil` when the
    /// user chose to export without one, or there is no vault key yet.
    public static func buildArchive(
        db: AppDatabase,
        appVersion: String,
        exportedAt: Date = Date(),
        vaultKey: FoldWrappedVaultKeyDTO? = nil
    ) throws -> FoldArchive {
        var tables: [BackupTableDump] = []
        try db.pool.read { conn in
            for spec in BackupTables.v1 {
                let rows = try Row.fetchAll(conn, sql: "SELECT * FROM \(spec.table)").map(Self.backupRow(from:))
                tables.append(BackupTableDump(
                    file: "journal", table: spec.table, rowCount: rows.count,
                    checksum: BackupChecksum.checksumFor(rows), rows: rows
                ))
            }
        }
        return FoldArchive(
            appVersion: appVersion, exportedAt: exportedAt.ISO8601Format(),
            tables: tables, vaultKey: vaultKey
        )
    }

    /// Serializes the archive the same way `parse(_:)`/`BackupImporter` reads
    /// it back — plain JSON, sorted keys for a stable byte layout (a
    /// diffable, reproducible export; RN's own `JSON.stringify(archive, null,
    /// 2)` is pretty-printed for the same "human can diff two exports"
    /// reason, format bytes themselves are never compared cross-language).
    public static func serialize(_ archive: FoldArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(archive)
    }

    static func backupRow(from row: Row) -> BackupRow {
        var out: BackupRow = [:]
        for columnName in row.columnNames {
            let dbValue: DatabaseValue = row[columnName]
            out[columnName] = BackupValue(dbValue)
        }
        return out
    }
}

extension BackupValue {
    init(_ dbValue: DatabaseValue) {
        switch dbValue.storage {
        case .null: self = .null
        case .int64(let i): self = .int(i)
        case .double(let d): self = .double(d)
        case .string(let s): self = .string(s)
        case .blob(let data): self = .string(data.base64EncodedString())
        }
    }

    /// The inverse of `init(_ dbValue:)` — used by `BackupImporter` to bind a
    /// row's values back into an `INSERT`.
    var databaseValue: DatabaseValue {
        switch self {
        case .string(let s): return s.databaseValue
        case .int(let i): return i.databaseValue
        case .double(let d): return d.databaseValue
        case .null: return .null
        }
    }
}
