import Foundation
import Testing
import JIPersistence
import JIVault
@testable import JIFeatures

@Test @MainActor func exportBuildsADocumentReadyForTheExporter() throws {
    let db = try AppDatabase.inMemory()
    let vm = BackupViewModel(db: db, cipher: IdentityCipher(), appVersion: "test-1.0")
    vm.export()
    #expect(vm.exportError == nil)
    #expect(vm.exportDocument != nil)
    #expect(vm.showExporter == true)
}

@Test @MainActor func pickedFileWithInvalidJSONShowsAFriendlyError() throws {
    let db = try AppDatabase.inMemory()
    let vm = BackupViewModel(db: db, cipher: IdentityCipher(), appVersion: "test-1.0")
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-backup-\(UUID().uuidString).json")
    try "not json".write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }

    vm.pickedFile(.success(tmp))

    guard case .failure(let message) = vm.importStage else { Issue.record("expected .failure, got \(vm.importStage)"); return }
    #expect(message.contains("valid JSON"))
}

@Test @MainActor func pickedFileWithOwnExportPreviewsAndRestores() async throws {
    let db = try AppDatabase.inMemory()
    try await db.pool.write { conn in
        try conn.execute(sql: "INSERT INTO goals (id, title, target_date, progress, created_at) VALUES (1, 'Deadlift 100kg', NULL, 0.5, '2026-09-01T00:00:00.000Z')")
    }
    let archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    let data = try BackupExporter.serialize(archive)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("own-export-\(UUID().uuidString).json")
    try data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let target = try AppDatabase.inMemory()
    let vm = BackupViewModel(db: target, cipher: IdentityCipher(), appVersion: "test-1.0")
    vm.pickedFile(.success(tmp))

    guard case .previewing(let preview) = vm.importStage else { Issue.record("expected .previewing, got \(vm.importStage)"); return }
    #expect(preview.hasVaultKey == false)
    let goalsRow = try #require(preview.rows.first { $0.table == "goals" })
    #expect(goalsRow.incomingRowCount == 1)
    #expect(goalsRow.currentRowCount == 0)

    await vm.confirmRestore()
    guard case .restored = vm.importStage else { Issue.record("expected .restored, got \(vm.importStage)"); return }
    let title: String = try await target.pool.read { conn in try String.fetchOne(conn, sql: "SELECT title FROM goals WHERE id = 1") ?? "" }
    #expect(title == "Deadlift 100kg")
}

@Test @MainActor func cancelImportClearsPendingStateWithoutWriting() throws {
    let db = try AppDatabase.inMemory()
    try db.pool.write { conn in
        try conn.execute(sql: "INSERT INTO goals (id, title, target_date, progress, created_at) VALUES (1, 'x', NULL, 0, '2026-09-01T00:00:00.000Z')")
    }
    let archive = try BackupExporter.buildArchive(db: db, appVersion: "test-1.0")
    let data = try BackupExporter.serialize(archive)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-\(UUID().uuidString).json")
    try data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let target = try AppDatabase.inMemory()
    let vm = BackupViewModel(db: target, cipher: IdentityCipher(), appVersion: "test-1.0")
    vm.pickedFile(.success(tmp))
    guard case .previewing = vm.importStage else { Issue.record("expected .previewing, got \(vm.importStage)"); return }

    vm.cancelImport()
    guard case .idle = vm.importStage else { Issue.record("expected .idle, got \(vm.importStage)"); return }
    let count: Int = try target.pool.read { conn in try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM goals") ?? -1 }
    #expect(count == 0)
}
