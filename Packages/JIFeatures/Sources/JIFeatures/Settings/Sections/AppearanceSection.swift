import SwiftUI
import JIDesign

/// W5a-L1 (P-appearance): the RN "Preferences → Appearance" row (`settings.tsx` L564–579)
/// → `AppearanceView`. Sits after L0's Goals / My KPIs links in the Preferences band.
public struct AppearanceSection: SettingsSection {
    public static let sectionId = "l1.appearance"
    public let id = Self.sectionId
    public let title = "Appearance"
    public let systemImage = "paintpalette"
    public let sortKey = SettingsSortKey.preferences + 20
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { AppearanceSectionRows() }
}

private struct AppearanceSectionRows: View {
    @Environment(SettingsViewModel.self) private var model
    /// Re-read on every appear, so coming back from the Appearance screen shows the new mode.
    @State private var mode: ThemeMode?

    var body: some View {
        SettingsRowGroup {
            NavigationLink { AppearanceView(model: AppearanceViewModel(prefs: model.prefs)) } label: {
                SettingsLinkLabel(title: "Appearance", systemImage: "paintpalette", trailing: mode?.label)
            }
            .onAppear { mode = ThemePrefsStore.load(from: model.prefs).mode }
            .accessibilityLabel("Appearance")
            .accessibilityIdentifier("settings.row.appearance")
        }
    }
}
