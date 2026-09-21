import SwiftUI
import JIDesign
import JIPersistence

/// Read-only preview shown before a restore actually overwrites anything —
/// mirrors RN `backup.tsx`'s pre-confirm table, one row per archive table
/// with current-vs-incoming row counts. A table this device's schema
/// doesn't have yet (`migratesInW5`) shows "migrates in W5" instead of a
/// count, per the W4 card's "listed, never silently dropped" rule.
public struct RestorePreviewView: View {
    @Environment(\.jiTheme) private var theme
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
                .jiFont(.footnote)
                .foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("restore-preview-header")

            // §2b.2: one 44-pt row per table instead of a hand-spaced HStack.
            ForEach(preview.rows, id: \.table) { row in
                if row.migratesInW5 {
                    JIRow(title: row.table) { Text("migrates in W5").jiFont(.caption) }
                        .accessibilityLabel("\(row.table), migrates in W5")
                } else {
                    JIRow(title: row.table) { Text("\(row.currentRowCount) → \(row.incomingRowCount)").jiFont(.caption) }
                        .accessibilityLabel("\(row.table), \(row.currentRowCount) rows now, \(row.incomingRowCount) after restore")
                }
            }

            if preview.hasVaultKey {
                SecureField("Backup passphrase", text: $passphrase)
                    .accessibilityIdentifier("restore-passphrase")
                    .accessibilityLabel("Backup passphrase")
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .accessibilityIdentifier("restore-cancel")
                Spacer()
                Button("Restore") { onConfirm() }
                    .tint(theme.color(.info))
                    .disabled(preview.hasVaultKey && passphrase.isEmpty)
                    .accessibilityIdentifier("restore-confirm")
                    .accessibilityHint("Replaces this device's data with the backup shown above.")
            }
        }
        .padding(.vertical, 4)
    }
}
