import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import JIPersistence
import JIVault

/// Wraps `Data` as a picker-facing `FileDocument` for `.fileExporter` — the
/// archive itself is already-serialized JSON (`BackupExporter.serialize`),
/// so this document has no knowledge of `FoldArchive`.
public struct BackupArchiveDocument: FileDocument, Sendable {
    public static var readableContentTypes: [UTType] { [.json] }
    public static var writableContentTypes: [UTType] { [.json] }
    public var data: Data
    public init(data: Data) { self.data = data }
    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Drives `BackupView` — export (`.fileExporter`, no entitlement) and
/// restore (`.fileImporter` → `BackupImporter.parse`/`preview` →
/// user-confirmed `BackupImporter.restore`). Mirrors RN `app/backup.tsx`'s
/// shape: pick a file, show a preview with row-count deltas (and a
/// passphrase field when the archive carries a wrapped vault key), then
/// confirm before anything is overwritten.
@Observable @MainActor
public final class BackupViewModel {
    public enum ImportStage: Sendable {
        case idle
        case previewing(BackupImportPreview)
        case restoring
        case restored(tableCount: Int)
        case failure(String)
    }

    public private(set) var exportDocument: BackupArchiveDocument?
    public private(set) var exportError: String?
    public var showExporter = false

    public private(set) var importStage: ImportStage = .idle
    public var passphrase: String = ""
    private var pendingArchive: FoldArchive?

    private let db: AppDatabase
    private let cipher: any FieldCipher
    private let appVersion: String

    public init(db: AppDatabase, cipher: any FieldCipher, appVersion: String) {
        self.db = db
        self.cipher = cipher
        self.appVersion = appVersion
    }

    public func export() {
        exportError = nil
        do {
            let archive = try BackupExporter.buildArchive(db: db, appVersion: appVersion)
            let data = try BackupExporter.serialize(archive)
            exportDocument = BackupArchiveDocument(data: data)
            showExporter = true
        } catch {
            exportError = "Couldn't build the backup — try again."
        }
    }

    public func pickedFile(_ result: Result<URL, any Error>) {
        importStage = .idle
        switch result {
        case .failure:
            importStage = .failure("Couldn't read that file.")
        case .success(let url):
            loadArchive(from: url)
        }
    }

    private func loadArchive(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importStage = .failure("Couldn't read that file.")
            return
        }
        switch BackupImporter.parse(data) {
        case .failure(let error):
            importStage = .failure(Self.describe(error))
        case .success(let archive):
            do {
                let preview = try BackupImporter.preview(archive, db: db)
                pendingArchive = archive
                importStage = .previewing(preview)
            } catch {
                importStage = .failure("Couldn't read the current data to compare against.")
            }
        }
    }

    public func confirmRestore() async {
        guard let archive = pendingArchive else { return }
        importStage = .restoring
        do {
            try BackupImporter.restore(archive, passphrase: passphrase.isEmpty ? nil : passphrase, targetCipher: cipher, db: db)
            importStage = .restored(tableCount: archive.tables.count)
            pendingArchive = nil
            passphrase = ""
        } catch let error as BackupImportError {
            importStage = .failure(Self.describe(error))
        } catch {
            importStage = .failure("Restore failed — try again.")
        }
    }

    public func cancelImport() {
        pendingArchive = nil
        passphrase = ""
        importStage = .idle
    }

    /// One clear, user-facing sentence per `BackupImportError` — mirrors RN
    /// `archive.ts`'s `describeParseFailure`.
    private static func describe(_ error: BackupImportError) -> String {
        switch error {
        case .invalidJSON:
            return "That file isn't readable as a backup — it doesn't look like valid JSON."
        case .notABackup:
            return "That file isn't a HealthTraining backup."
        case .versionMismatch(let found):
            return "This backup was made with a different app version (format v\(found)) and can't be restored here."
        case .corrupted(let table):
            return "This backup looks corrupted — \"\(table)\" failed its integrity check."
        case .wrongPassphrase:
            return "That passphrase doesn't match this backup's vault key."
        case .passphraseRequired:
            return "This backup is vault-protected — enter its passphrase to restore."
        }
    }
}
