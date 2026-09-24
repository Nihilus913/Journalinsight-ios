import SwiftUI
import JICore
import JIHub
import JIPersistence

// W5b-L3 (P-gate-config). RN `settings.tsx` Preferences card "Gate config" → pushes `GateConfigView`
// (RN `app/gate-config.tsx`). Sits after Edit Today in the Preferences band.
public struct GateConfigSection: SettingsSection {
    public static let sectionId = "w5b.gateConfig"
    public let id = Self.sectionId
    public let title = "Gate config"
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
                GateConfigView(model: GateConfigViewModel(targetsProvider: Self.hubTargetsProvider(), prefStore: model.prefs))
            } label: {
                SettingsLinkLabel(title: "Gate config", subtitle: "Local threshold overrides, fixture preview, live KPI targets",
                                  systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Gate config")
            .accessibilityIdentifier("settings.row.gateConfig")
        }
    }

    /// `SettingsViewModel` is frozen after W5a-L0 (a lane adds a section, never a field — see
    /// `ProviderSwitch`), and the hub provider it holds for "My KPIs" is private to that model. The
    /// live KPI-target block is hub-only by nature (`plan.kpi_target` rows), so this section builds
    /// the SAME `HubDataProvider` the app does from the saved connection (`ConnectionConfigStore`,
    /// Keychain-backed — rule 2: the token never leaves the Keychain except into a `HubClient`).
    /// No saved connection → `nil` → the screen's server block explains itself (rule 5).
    private static func hubTargetsProvider() -> (any KpiTargetsProviding)? {
        guard let config = try? ConnectionConfigStore().load() else { return nil }
        return HubDataProvider(client: HubClient(config: config))
    }
}
