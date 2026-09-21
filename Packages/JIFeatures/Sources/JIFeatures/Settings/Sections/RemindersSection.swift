import SwiftUI
import UserNotifications
import JIDesign
import JIPersistence

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
                RemindersDestination(prefs: model.prefs)
            } label: {
                SettingsLinkLabel(title: "Reminders", subtitle: RemindersCopy.header)
            }
            .accessibilityLabel("Reminders")
            .accessibilityIdentifier("settings.row.reminders")
        }
    }
}

/// The destination is a view of its own so `UNUserNotificationCenter.current()` runs when
/// Reminders is actually pushed, not while the Settings list builds its rows. `NavigationLink`'s
/// destination closure is evaluated eagerly at `body` time, and the notification centre throws
/// `bundleProxyForCurrentProcess is nil` in a host-app-less test process — which is what crashed
/// the §8.5 sweep on the "Settings" entry.
private struct RemindersDestination: View {
    let prefs: PrefStore
    var body: some View {
        RemindersView(model: RemindersViewModel(
            scheduler: ReminderScheduler(center: UNUserNotificationCenter.current()),
            prefs: prefs
        ))
    }
}
