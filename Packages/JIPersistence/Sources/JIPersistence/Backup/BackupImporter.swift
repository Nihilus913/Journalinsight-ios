import Foundation
import GRDB
import JIVault

/// Failure reasons surfaced to the UI — mirrors RN `archive.ts`'s
/// `ParseArchiveResult`/`WrongPassphraseError` split, one distinct case per
/// user-facing reason rather than a single generic "invalid file" error.
public enum BackupImportError: Error, Equatable, Sendable {
    case invalidJSON
    case notABackup
    case versionMismatch(found: Int)
    /// Names the `file.table` whose `rowCount`/checksum didn't match its own
    /// `rows` payload.
    case corrupted(table: String)
    /// The archive carries a wrapped vault key and the passphrase didn't
    /// unwrap it (MAC mismatch) — mirrors RN's `WrongPassphraseError`. No
    /// rows are written when this is thrown: `restore(_:...)` unwraps the
    /// key BEFORE opening any GRDB transaction.
    case wrongPassphrase
    /// The archive carries a wrapped vault key but the caller passed no
    /// passphrase to unwrap it.
    case passphraseRequired
}

/// One table's row-count delta for the restore-confirmation screen — mirrors
/// RN `archive.ts`'s `RestorePreviewRow`. `migratesInW5` is true for a table
/// this device's schema doesn't have yet (`BackupTables.notYetMigrated`):
/// listed, never silently dropped, and never written by `restore(_:...)`.
public struct BackupImportPreviewRow: Sendable, Equatable {
    public let table: String
    public let currentRowCount: Int
    public let incomingRowCount: Int
    public let migratesInW5: Bool
}

public struct BackupImportPreview: Sendable, Equatable {
    public let appVersion: String
    public let exportedAt: String
    public let rows: [BackupImportPreviewRow]
    public let hasVaultKey: Bool
}

public enum BackupImporter {
    // MARK: - Parse + validate

    /// Validates format marker, exact schema version, and every table's
    /// checksum+rowCount against its own row payload — mirrors RN's
    /// `parseBackupArchive`. Order matters the same way: JSON/format failures
    /// are reported before a version check, which is reported before any
    /// per-table integrity check. Decodes through `FoldArchive.decodeOrdered`
    /// so each row's keys keep their document order — the order RN hashed;
    /// a `JSONDecoder` decode would scramble them and every real Fold
    /// archive would read as `.corrupted`.
    public static func parse(_ raw: Data) -> Result<FoldArchive, BackupImportError> {
        let archive: FoldArchive
        do {
            archive = try FoldArchive.decodeOrdered(raw)
        } catch {
            return .failure(.invalidJSON)
        }
        guard archive.format == FoldArchive.format else { return .failure(.notABackup) }
        guard archive.schemaVersion == FoldArchive.schemaVersion else {
            return .failure(.versionMismatch(found: archive.schemaVersion))
        }
        for t in archive.tables {
            guard t.rows.count == t.rowCount, BackupChecksum.checksumFor(t.rows) == t.checksum else {
                return .failure(.corrupted(table: "\(t.file).\(t.table)"))
            }
        }
        return .success(archive)
    }

    // MARK: - Preview (read-only)

    public static func preview(_ archive: FoldArchive, db: AppDatabase) throws -> BackupImportPreview {
        var rows: [BackupImportPreviewRow] = []
        try db.pool.read { conn in
            for t in archive.tables {
                let migratesInW5 = BackupTables.spec(for: t.table) == nil
                let currentCount: Int
                if migratesInW5 {
                    currentCount = 0
                } else {
                    currentCount = (try? Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(t.table)")) ?? 0
                }
                rows.append(BackupImportPreviewRow(
                    table: t.table, currentRowCount: currentCount,
                    incomingRowCount: t.rowCount, migratesInW5: migratesInW5
                ))
            }
        }
        return BackupImportPreview(
            appVersion: archive.appVersion, exportedAt: archive.exportedAt,
            rows: rows, hasVaultKey: archive.vaultKey != nil
        )
    }

    // MARK: - Restore

    /// Overwrites every W4-schema table the archive carries (DELETE-then-
    /// INSERT, matching RN's `restoreTable`) inside ONE GRDB transaction — a
    /// failure partway through rolls every table back rather than leaving a
    /// referentially-broken mix (mirrors RN `archive.ts`'s
    /// `restoreTablesInTransaction`). Tables not in `BackupTables.v1` (see
    /// `preview(_:db:)`'s `migratesInW5`) are skipped, never written.
    ///
    /// If the archive carries a wrapped vault key, `passphrase` unwraps it
    /// via `FoldImportBridge` BEFORE the transaction opens — a wrong
    /// passphrase throws `.wrongPassphrase` with no GRDB write attempted.
    /// Every vaulted column (`BackupTableSpec.vaultedColumns`) is decrypted
    /// from its RN `htv1:` form via `FoldImportBridge.decryptColumn` and
    /// immediately re-sealed under `targetCipher` — the column this writes
    /// is always `targetCipher`'s own envelope, never RN's ciphertext, so a
    /// later `open` reads back through the same cipher every other W4 store
    /// uses.
    public static func restore(
        _ archive: FoldArchive,
        passphrase: String?,
        targetCipher: any FieldCipher,
        db: AppDatabase
    ) throws {
        let rawKeyHex: String?
        if let wrapped = archive.vaultKey {
            guard let passphrase, !passphrase.isEmpty else { throw BackupImportError.passphraseRequired }
            let bridgeWrapped = FoldWrappedVaultKey(
                version: wrapped.version, saltHex: wrapped.saltHex, ivHex: wrapped.ivHex,
                iterations: wrapped.iterations, ciphertextB64: wrapped.ciphertextB64, macHex: wrapped.macHex
            )
            do {
                rawKeyHex = try FoldImportBridge.unwrapVaultKey(bridgeWrapped, passphrase: passphrase)
            } catch {
                throw BackupImportError.wrongPassphrase
            }
        } else {
            rawKeyHex = nil
        }

        let knownTables = archive.tables.filter { BackupTables.spec(for: $0.table) != nil }

        try db.pool.write { conn in
            for t in knownTables {
                guard let spec = BackupTables.spec(for: t.table) else { continue }
                try conn.execute(sql: "DELETE FROM \(t.table)")
                for row in t.rows {
                    let resealed = try Self.resealVaultedColumns(row, spec: spec, rawKeyHex: rawKeyHex, targetCipher: targetCipher)
                    guard !resealed.isEmpty else { continue }
                    let columns = resealed.keys
                    let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
                    let arguments = StatementArguments(columns.map { resealed[$0]!.databaseValue })
                    try conn.execute(
                        sql: "INSERT INTO \(t.table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))",
                        arguments: arguments
                    )
                }
            }
        }
    }

    /// Only an RN `htv1:`-marked value, with a `rawKeyHex` unwrapped from the
    /// archive's vault key, is decrypted and re-sealed. Everything else
    /// (already this app's own `jiv1:` envelope — the normal case when
    /// restoring this app's own prior export back onto itself — or plain
    /// legacy text) passes through byte-for-byte unchanged: it is already in
    /// the form `FieldCipher.open` on this device expects, and re-sealing it
    /// again would double-wrap it.
    private static func resealVaultedColumns(
        _ row: BackupRow, spec: BackupTableSpec, rawKeyHex: String?, targetCipher: any FieldCipher
    ) throws -> BackupRow {
        guard !spec.vaultedColumns.isEmpty, let rawKeyHex else { return row }
        var out = row
        for column in spec.vaultedColumns {
            guard let value = row[column], case .string(let stored) = value, stored.hasPrefix("htv1:") else { continue }
            let plain = try FoldImportBridge.decryptColumn(stored, rawKeyHex: rawKeyHex)
            out[column] = .string(try targetCipher.seal(plain))
        }
        return out
    }
}
