import SwiftUI

// W5a-L3 (P-edit-today). RN `settings.tsx` Preferences card "Edit Today" → pushes `EditTodayView`.
// Sits after the L0 Goals/My KPIs links in the Preferences band.
public struct EditTodaySection: SettingsSection {
    public static let sectionId = "l3.editToday"
    public let id = Self.sectionId
    public let title = "Edit Today"
    public let systemImage = "square.grid.2x2"
    public let sortKey = SettingsSortKey.preferences + 10
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { EditTodaySectionRows() }
}

private struct EditTodaySectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Section {
            NavigationLink { EditTodayView(model: EditTodayViewModel(prefs: model.prefs)) } label: {
                SettingsLinkLabel(title: "Edit Today", subtitle: "Choose which tiles show, and their order")
            }
            .accessibilityLabel("Edit Today")
            .accessibilityIdentifier("settings.row.editToday")
        }
    }
}
