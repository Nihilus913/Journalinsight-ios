import SwiftUI
import JIDesign
import JIPersistence

// W5a-L4 (P-version). RN `settings.tsx` "Advanced" → "About & version" row:
// "{APP_NAME} {APP_VERSION} — what changed in this build". Gate & KPI thresholds (W5b) adds its
// own section in this band.
public struct VersionSection: SettingsSection {
    public static let sectionId = "l4.version"
    public let id = Self.sectionId
    public let title = "About & version"
    public let systemImage = "info.circle"
    public let sortKey = SettingsSortKey.advanced + 50
    public let group = SettingsGroupId.about
    public init() {}
    public var body: some View { VersionSectionRows() }
}

private struct VersionSectionRows: View {
    @Environment(SettingsViewModel.self) private var model
    private let info = VersionInfo()

    var body: some View {
        SettingsRowGroup(header: SettingsGroup.advanced.title) {
            NavigationLink {
                VersionView(model: VersionViewModel(prefs: model.prefs, info: info),
                            thisInstall: VersionInstallState(
                                hub: settingsHubSubtitle(host: model.connection.host, lastSync: model.lastSyncDate, now: Date()),
                                hubConnected: { if case .ok? = model.connection.status { true } else { false } }()))
            } label: {
                SettingsLinkLabel(title: "About & version", systemImage: "info.circle", trailing: info.appVersion)
            }
            .accessibilityLabel("About & version")
            .accessibilityIdentifier("settings.row.version")
        }
    }
}
