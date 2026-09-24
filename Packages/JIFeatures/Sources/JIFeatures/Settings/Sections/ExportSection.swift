import SwiftUI
import JIPersistence
import JIVault

// W5b-L5 (P-export). Settings → Data row "Export" → pushes `ExportView`. RN reaches `/export` from
// the Journal tab's share icon (`journal.tsx:85`); `JournalView.swift` is another lane's file, so
// per the W5b card this lane's entry is its Settings section (RN's Data band, after Backup).
//
// `SettingsViewModel` (frozen) exposes no database or cipher (`BackupViewModel` keeps its own
// private), so this row resolves them exactly the way `RootTabView.makeSettingsModel()` does: the
// backed-up `journalinsight.sqlite` pool plus the vault's session cipher (`VaultManager.unlock()`
// is a Keychain load-or-generate, never an interactive prompt). Until that resolves the row
// explains itself rather than vanishing (rule 5).
public struct ExportSection: SettingsSection {
    public static let sectionId = "l5.export"
    public let id = Self.sectionId
    public let title = "Export"
    public let systemImage = "square.and.arrow.up"
    public let sortKey = SettingsSortKey.data + 5
    public let group = SettingsGroupId.sync
    public init() {}
    public var body: some View { ExportSectionRows() }
}

private struct ExportSectionRows: View {
    @State private var stores: ExportViewModel.Stores?
    @State private var unavailable = false

    var body: some View {
        Section {
            if let stores {
                NavigationLink { ExportView(model: ExportViewModel(stores: stores)) } label: {
                    SettingsLinkLabel(title: "Export", subtitle: settingsDataSubtitles["Export"] ?? "")
                }
                .accessibilityLabel("Export")
                .accessibilityIdentifier("settings.row.export")
            } else if unavailable {
                SettingsLinkLabel(title: "Export", subtitle: "The on-device vault couldn't be opened — open the Journal tab once, then come back")
                    .accessibilityIdentifier("settings.row.export.unavailable")
            } else {
                SettingsLinkLabel(title: "Export", subtitle: "Preparing…")
                    .accessibilityIdentifier("settings.row.export.preparing")
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        guard stores == nil else { return }
        guard let db = try? AppDatabase.onDisk(),
              let cipher = try? await VaultManager(keychain: SecureKeychainService()).unlock()
        else { unavailable = true; return }
        stores = ExportViewModel.Stores(
            journal: JournalStore(db: db, cipher: cipher),
            checkins: CheckInStore(db: db, cipher: cipher),
            events: EventStore(db: db, cipher: cipher),
            who5: Who5Store(db: db, cipher: cipher),
            goals: GoalStore(db: db)
        )
    }
}
