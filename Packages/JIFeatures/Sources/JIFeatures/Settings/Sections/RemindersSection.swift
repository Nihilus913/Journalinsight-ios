import SwiftUI
import UserNotifications
import JIDesign

// W5a-L2 (P-reminders): the "Reminders" row in RN's Data band (RN reaches `reminders.tsx` from
// the Journal tab's bell; the Swift Settings registry is its home per the W5a card).
public struct RemindersSection: SettingsSection {
    public static let sectionId = "l2.reminders"
    public let id = Self.sectionId
    public let title = "Reminders"
    public let systemImage = "bell"
    public let sortKey = SettingsSortKey.data + 10
    public init() {}
    public var body: some View { RemindersSectionRows() }
}

private struct RemindersSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Section("Reminders") {
            NavigationLink {
                RemindersView(model: RemindersViewModel(
                    scheduler: ReminderScheduler(center: UNUserNotificationCenter.current()),
                    prefs: model.prefs
                ))
            } label: {
                SettingsLinkLabel(title: "Reminders", subtitle: RemindersCopy.header)
            }
            .accessibilityLabel("Reminders")
            .accessibilityIdentifier("settings.row.reminders")
        }
    }
}
