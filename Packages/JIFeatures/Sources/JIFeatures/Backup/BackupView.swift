import SwiftUI
import UniformTypeIdentifiers
import JIDesign

/// "Backup & restore" screen (`Settings/ConnectionSheet.swift` pushes this).
/// No file-access entitlement is needed: `.fileExporter`/`.fileImporter` use
/// the system document picker, same as RN's share-sheet-based export.
public struct BackupView: View {
    @State private var model: BackupViewModel
    @State private var showImporter = false

    public init(model: BackupViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            Section("Export") {
                Button("Export backup") { model.export() }
                    .accessibilityIdentifier("backup-export")
                    .accessibilityHint("Opens the system save sheet for the backup file.")
                if let error = model.exportError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("backup-export-error")
                }
            }
            Section("Restore") {
                Button("Choose backup file…") { showImporter = true }
                    .accessibilityIdentifier("backup-choose-file")
                    .accessibilityHint("Opens the system file picker to choose a backup to restore.")
                importStageView
            }
        }
        .navigationTitle("Backup & restore")
        .fileExporter(
            isPresented: $model.showExporter,
            document: model.exportDocument,
            contentType: .json,
            defaultFilename: "healthtraining-backup"
        ) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            model.pickedFile(result)
        }
    }

    @ViewBuilder private var importStageView: some View {
        switch model.importStage {
        case .idle:
            EmptyView()
        case .previewing(let preview):
            RestorePreviewView(
                preview: preview,
                passphrase: $model.passphrase,
                onConfirm: { Task { await model.confirmRestore() } },
                onCancel: { model.cancelImport() }
            )
        case .restoring:
            HStack { Text("Restoring…"); Spacer(); ProgressView() }
                .accessibilityIdentifier("backup-restoring")
        case .restored(let count):
            Text("Restored \(count) tables.").foregroundStyle(JIColor.info)
                .accessibilityIdentifier("backup-restored")
        case .failure(let message):
            Text(message).font(.footnote).foregroundStyle(.red)
                .accessibilityIdentifier("backup-restore-error")
        }
    }
}
