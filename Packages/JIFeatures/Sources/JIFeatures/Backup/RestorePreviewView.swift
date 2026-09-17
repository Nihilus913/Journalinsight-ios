import SwiftUI
import JIDesign
import JIPersistence

/// Read-only preview shown before a restore actually overwrites anything —
/// mirrors RN `backup.tsx`'s pre-confirm table, one row per archive table
/// with current-vs-incoming row counts. A table this device's schema
/// doesn't have yet (`migratesInW5`) shows "migrates in W5" instead of a
/// count, per the W4 card's "listed, never silently dropped" rule.
public struct RestorePreviewView: View {
    let preview: BackupImportPreview
    @Binding var passphrase: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(
        preview: BackupImportPreview,
        passphrase: Binding<String>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.preview = preview
        self._passphrase = passphrase
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup from \(preview.exportedAt) · app \(preview.appVersion)")
                .font(.footnote)
                .foregroundStyle(JIColor.muted)

            ForEach(preview.rows, id: \.table) { row in
                HStack {
                    Text(row.table)
                    Spacer()
                    if row.migratesInW5 {
                        Text("migrates in W5").font(.caption).foregroundStyle(JIColor.muted)
                    } else {
                        Text("\(row.currentRowCount) → \(row.incomingRowCount)").font(.caption)
                    }
                }
            }

            if preview.hasVaultKey {
                SecureField("Backup passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                Spacer()
                Button("Restore") { onConfirm() }
                    .tint(JIColor.info)
                    .disabled(preview.hasVaultKey && passphrase.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }
}
