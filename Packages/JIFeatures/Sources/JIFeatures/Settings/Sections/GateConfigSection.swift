import SwiftUI
import JICore
import JIHub
import JIPersistence
import UserNotifications

// W5b-L3 (P-gate-config). RN `settings.tsx` Preferences card "Gate config" → pushes `GateConfigView`
// (RN `app/gate-config.tsx`). Sits after Edit Today in the Preferences band.
public struct GateConfigSection: SettingsSection {
    public static let sectionId = "w5b.gateConfig"
    public let id = Self.sectionId
    public let title = "Gate thresholds"
    public let systemImage = "slider.horizontal.3"
    public let sortKey = SettingsSortKey.preferences + 20
    public let group = SettingsGroupId.kpis
    public init() {}
    public var body: some View { GateConfigSectionRows() }
}

private struct GateConfigSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        SettingsRowGroup {
            NavigationLink {
                GateConfigDestination(prefs: model.prefs)
            } label: {
                SettingsLinkLabel(title: "Gate thresholds", subtitle: "How cautious, your HR cap and zones, threshold overrides",
                                  systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Gate thresholds")
            .accessibilityIdentifier("settings.row.gateConfig")
        }
    }

    /// `SettingsViewModel` is frozen after W5a-L0 (a lane adds a section, never a field — see
    /// `ProviderSwitch`), and the hub provider it holds for "My KPIs" is private to that model. The
    /// live KPI-target block is hub-only by nature (`plan.kpi_target` rows), so this section builds
    /// the SAME `HubDataProvider` the app does from the saved connection (`ConnectionConfigStore`,
    /// Keychain-backed — rule 2: the token never leaves the Keychain except into a `HubClient`).
    /// No saved connection → `nil` → the screen's server block explains itself (rule 5).
    static func hubProvider() -> HubDataProvider? {
        guard let config = try? ConnectionConfigStore().load() else { return nil }
        return HubDataProvider(client: HubClient(config: config))
    }
}

/// B-57 W4: built only when the row is pushed (the `RemindersDestination` pattern), so
/// `UNUserNotificationCenter.current()` is never touched while the Settings list builds in the
/// host-less test process. The mirror copies gate-settings changes to the hub.
private struct GateConfigDestination: View {
    let prefs: PrefStore
    var body: some View {
        let hub = GateConfigSectionRows.hubProvider()
        GateConfigView(model: GateConfigViewModel(
            targetsProvider: hub, prefStore: prefs,
            mirror: GateSettingsMirror(prefs: prefs, provider: hub),
            reminderCenter: UNUserNotificationCenter.current()))
    }
}
