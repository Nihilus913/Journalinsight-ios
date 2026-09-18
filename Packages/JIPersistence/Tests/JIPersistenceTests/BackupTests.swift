import Foundation
import Testing
import GRDB
import CryptoKit
@testable import JIPersistence

/// In-memory `KeychainService` double, local to this test target (JIVault's
/// own `FakeKeychain` lives in `JIVaultTests`, not exported). Mirrors that
/// file's shape.
private actor FakeBackupKeychain: KeychainService {
    private var stored: Data?
    func loadMasterKey() async throws -> SymmetricKey {
        guard let data = stored else { throw KeychainError.itemNotFound }
        return SymmetricKey(data: data)
    }
    func storeNewMasterKey() async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        stored = key.withUnsafeBytes { Data($0) }
        return key
    }
    func deleteMasterKey() async throws { stored = nil }
}

private func insertSampleEntry(_ db: AppDatabase, cipher: any FieldCipher, id: Int64 = 1) throws {
    try db.pool.write { conn in
        try conn.execute(
            sql: """
            INSERT INTO entries (id, date, ts, text, duration_sec, mood, created_at, updated_at, synced)
            VALUES (?, ?, ?, ?, 0, ?, ?, ?, 0)
            """,
            arguments: [
                id, "2026-09-08", "2026-09-08T07:00:00.000Z",
                try cipher.seal("hello from a test"), try cipher.seal("good"),
                "2026-09-08T07:00:00.000Z", "2026-09-08T07:00:00.000Z",
            ]
        )
    }
}

// MARK: - Export -> import round trip

@Test func exportWritesArchiveImporterReadsBack() throws {
    let db = try AppDatabase.inMemory()
    try insertSampleEntry(db, cipher: IdentityCipher())
    try db.pool.write { conn in
        try conn.execute(sql: "INSERT INTO tags (id, name) VALUES (1, 'training')")
        try conn.execute(sql: "INSERT INTO goals (id, title, target_date, progress, created_at) VALUES (1, 'Deadlift 100kg', NULL, 0.5, '2026-09-01T00:00:00.000Z')")
    }

    let archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    #expect(archive.format == FoldArchive.format)
    #expect(archive.schemaVersion == FoldArchive.schemaVersion)
    #expect(archive.tables.count == BackupTables.v1.count)

    let data = try BackupExporter.serialize(archive)
    let parsed = try #require(BackupImporter.parse(data).get() as FoldArchive?)

    let target = try AppDatabase.inMemory()
    try BackupImporter.restore(parsed, passphrase: nil, targetCipher: IdentityCipher(), db: target)

    let text: String = try target.pool.read { conn in try String.fetchOne(conn, sql: "SELECT text FROM entries WHERE id = 1") ?? "" }
    #expect(text == "hello from a test")
    let goalTitle: String = try target.pool.read { conn in try String.fetchOne(conn, sql: "SELECT title FROM goals WHERE id = 1") ?? "" }
    #expect(goalTitle == "Deadlift 100kg")
}

@Test func roundTripPreservesRealEnvelopeCiphertextNeverPlaintext() async throws {
    let vault = VaultManager(keychain: FakeBackupKeychain())
    let cipher = try await vault.unlock()

    let db = try AppDatabase.inMemory()
    try insertSampleEntry(db, cipher: cipher)

    // The raw column must never equal the plaintext.
    let rawText: String = try await db.pool.read { conn in try String.fetchOne(conn, sql: "SELECT text FROM entries WHERE id = 1") ?? "" }
    #expect(rawText != "hello from a test")

    let archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    let target = try AppDatabase.inMemory()
    try BackupImporter.restore(archive, passphrase: nil, targetCipher: cipher, db: target)

    let restoredRaw: String = try await target.pool.read { conn in try String.fetchOne(conn, sql: "SELECT text FROM entries WHERE id = 1") ?? "" }
    #expect(restoredRaw != "hello from a test")
    #expect(try cipher.open(restoredRaw) == "hello from a test")
}

// MARK: - Checksum / integrity

@Test func checksumMismatchNamesTheTable() throws {
    let db = try AppDatabase.inMemory()
    try insertSampleEntry(db, cipher: IdentityCipher())
    var archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    let idx = try #require(archive.tables.firstIndex { $0.table == "entries" })
    archive.tables[idx].checksum = "deadbeef"
    let data = try BackupExporter.serialize(archive)

    let result = BackupImporter.parse(data)
    switch result {
    case .failure(.corrupted(let table)):
        #expect(table == "journal.entries")
    default:
        Issue.record("expected .corrupted(table: journal.entries), got \(result)")
    }
}

@Test func rowCountMismatchIsAlsoCorrupted() throws {
    let db = try AppDatabase.inMemory()
    try insertSampleEntry(db, cipher: IdentityCipher())
    var archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    let idx = try #require(archive.tables.firstIndex { $0.table == "entries" })
    archive.tables[idx].rowCount = 99
    let data = try BackupExporter.serialize(archive)
    #expect(BackupImporter.parse(data).isFailure)
}

// MARK: - Fold-archive fixture (RN oracle format)

private struct FoldFixture {
    let passphrase: String
    let rawKeyHex: String
    let archive: FoldArchive
}

/// Loaded through the ordered scanner, never `JSONDecoder`: the fixture's
/// per-table checksums are RN's (`fnv1aHex(JSON.stringify(rows))`, keys in
/// column order), so the rows must keep their document order to verify.
private func loadFoldFixture() throws -> FoldFixture {
    let root = try OrderedJSON.parse(Data(FoldArchiveFixtureJSON.raw.utf8))
    return FoldFixture(
        passphrase: try root.requiredString("passphrase"),
        rawKeyHex: try root.requiredString("rawKeyHex"),
        archive: try FoldArchive(orderedJSON: try #require(root["archive"]))
    )
}

@Test func foldFixtureChecksumsAreRNComputedAndVerify() throws {
    // The raw fixture bytes, straight through the importer's own parse path:
    // every table's RN checksum must verify against its document-order rows.
    let fixture = try loadFoldFixture()
    for t in fixture.archive.tables {
        #expect(BackupChecksum.checksumFor(t.rows) == t.checksum, "table \(t.table)")
    }
    // And the raw fixture's archive bytes through the importer's own parse
    // path (`decodeOrdered` -> RN checksum verify), then a re-serialize.
    let root = try OrderedJSON.parse(Data(FoldArchiveFixtureJSON.raw.utf8))
    let rawArchive = Data(try #require(root["archive"]).serialized(indent: 2).utf8)
    #expect(try BackupImporter.parse(rawArchive).get() == fixture.archive)
    let reserialized = try BackupExporter.serialize(fixture.archive)
    let parsed = try #require(BackupImporter.parse(reserialized).get() as FoldArchive?)
    #expect(parsed == fixture.archive)
}

@Test func foldFixtureParsesAndListsUnmigratedTable() throws {
    let fixture = try loadFoldFixture()
    let archive = try #require(BackupImporter.parse(try BackupExporter.serialize(fixture.archive)).get() as FoldArchive?)
    #expect(archive.vaultKey != nil)

    let db = try AppDatabase.inMemory()
    let preview = try BackupImporter.preview(archive, db: db)
    let strengthRow = try #require(preview.rows.first { $0.table == "strength_state_local" })
    #expect(strengthRow.migratesInW5 == true)
    let entriesRow = try #require(preview.rows.first { $0.table == "entries" })
    #expect(entriesRow.migratesInW5 == false)
    #expect(entriesRow.incomingRowCount == 2)
}

@Test func foldImportWrongPassphraseThrowsAndWritesNoRows() throws {
    let fixture = try loadFoldFixture()
    let db = try AppDatabase.inMemory()
    #expect(throws: BackupImportError.wrongPassphrase) {
        try BackupImporter.restore(fixture.archive, passphrase: "not-the-passphrase", targetCipher: IdentityCipher(), db: db)
    }
    let count: Int = try db.pool.read { conn in try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries") ?? -1 }
    #expect(count == 0)
}

@Test func foldImportResealsVaultedColumnsAsEnvelope() async throws {
    let fixture = try loadFoldFixture()
    let vault = VaultManager(keychain: FakeBackupKeychain())
    let cipher = try await vault.unlock()

    let db = try AppDatabase.inMemory()
    try BackupImporter.restore(fixture.archive, passphrase: fixture.passphrase, targetCipher: cipher, db: db)

    let pairs: [(text: String, mood: String)] = try await db.pool.read { conn in
        try Row.fetchAll(conn, sql: "SELECT text, mood FROM entries ORDER BY id").map { ($0["text"] as String, $0["mood"] as String) }
    }
    #expect(pairs.count == 2)
    let rawText = pairs[0].text
    // The raw column is JIVault's own GCM envelope now, never RN's htv1: ciphertext.
    #expect(!rawText.hasPrefix("htv1:"))
    #expect(rawText.hasPrefix("jiv1:"))
    let openedText = try cipher.open(rawText)
    #expect(openedText == "Ate breakfast, felt okay.")
    let openedMood = try cipher.open(pairs[0].mood)
    #expect(openedMood == "good")
}

@Test func foldImportSkipsUnmigratedTableWithoutError() async throws {
    let fixture = try loadFoldFixture()
    let vault = VaultManager(keychain: FakeBackupKeychain())
    let cipher = try await vault.unlock()
    let db = try AppDatabase.inMemory()
    // No error, and the (unknown to this schema) strength_state_local table is simply skipped.
    try BackupImporter.restore(fixture.archive, passphrase: fixture.passphrase, targetCipher: cipher, db: db)
    let goalCount: Int = try await db.pool.read { conn in try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM goals") ?? -1 }
    #expect(goalCount == 2)
}

// MARK: - Transaction atomicity

@Test func restoreIsAtomicAcrossTablesOnFailure() throws {
    let db = try AppDatabase.inMemory()
    try db.pool.write { conn in
        try conn.execute(sql: "INSERT INTO tags (id, name) VALUES (1, 'pre-existing')")
    }
    var archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    // A well-formed `tags` table, followed by a `goals` row missing its
    // NOT NULL `title` — the INSERT for that row must fail, and the
    // `tags` DELETE+INSERT from the SAME transaction must roll back too.
    let tagsIdx = try #require(archive.tables.firstIndex { $0.table == "tags" })
    archive.tables[tagsIdx].rows = [["id": .int(2), "name": .string("should-not-persist")]]
    archive.tables[tagsIdx].rowCount = 1
    archive.tables[tagsIdx].checksum = BackupChecksum.checksumFor(archive.tables[tagsIdx].rows)

    let goalsIdx = try #require(archive.tables.firstIndex { $0.table == "goals" })
    archive.tables[goalsIdx].rows = [["id": .int(1), "target_date": .null, "progress": .double(0.1), "created_at": .string("2026-01-01T00:00:00.000Z")]]
    archive.tables[goalsIdx].rowCount = 1
    archive.tables[goalsIdx].checksum = BackupChecksum.checksumFor(archive.tables[goalsIdx].rows)

    #expect(throws: (any Error).self) {
        try BackupImporter.restore(archive, passphrase: nil, targetCipher: IdentityCipher(), db: db)
    }

    // `restore` writes each table in the archive's own file/table order; `tags` comes
    // before `goals` in BackupTables.v1, so its DELETE+failed-INSERT-group must have
    // rolled back with the transaction, leaving the ORIGINAL pre-existing row intact.
    let tagNames: [String] = try db.pool.read { conn in try String.fetchAll(conn, sql: "SELECT name FROM tags ORDER BY id") }
    #expect(tagNames == ["pre-existing"])
}

private extension Result {
    var isFailure: Bool { if case .failure = self { return true } else { return false } }
}
