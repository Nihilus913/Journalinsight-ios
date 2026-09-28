import SwiftUI
import JIDesign

// W-TGT fixer 1e (mock 04): Sync now leads Settings › Sync & hub — the root row's subtitle says
// when the hub last synced. It is the screen's ONE primary button; its state sits under it.
public struct SyncNowSection: SettingsSection {
    public nonisolated static let sectionId = "tgt.syncNow"
    public let id = Self.sectionId
    public let title = "Sync now"
    public let systemImage = "arrow.triangle.2.circlepath"
    public let sortKey = SettingsSortKey.connection
    public let group = SettingsGroupId.sync
    public init() {}
    public var body: some View { SyncNowRows() }
}

private struct SyncNowRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        if model.canSyncNow {
            Section {
                Button { Task { await model.syncNow() } } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.jiPrimary)
                .disabled(model.syncing)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Sync now")
                .accessibilityHint("Sends Apple Health to the hub, then asks the hub to sync Garmin and YAZIO")
                .accessibilityIdentifier("settings.root.syncNow")
            } footer: {
                Text(settingsSyncTrailing(syncing: model.syncing, failed: model.syncFailed, lastSync: model.lastSyncDate, now: Date()))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.root.syncNow.state")
            }
        }
    }
}
