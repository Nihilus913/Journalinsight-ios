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
    public let group = SettingsGroupId.haptics
    public init() {}
    public var body: some View { RemindersSectionRows() }
}

private struct RemindersSectionRows: View {
    @Environment(SettingsViewModel.self) private var model
    @Environment(\.jiOffscreenRender) private var offscreen
    @State private var trailing: String?

    var body: some View {
        SettingsRowGroup(header: "Reminders") {
            NavigationLink {
                RemindersDestination(prefs: model.prefs)
            } label: {
                SettingsLinkLabel(title: "Reminders", systemImage: "bell", trailing: trailing)
            }
            // W-FIX5 W4-3: the count includes the HR-cap re-check, which lives only as a pending
            // notification. `.task` re-runs each time the row reappears (back from Reminders).
            .task {
                let prefs = (try? model.prefs.get(RemindersPrefs.prefKey, as: RemindersPrefs.self)) ?? nil
                trailing = settingsRemindersTrailing(prefs)
                // Only in the app: the notification centre throws in a host-app-less test process.
                guard !offscreen, Bundle.main.bundleURL.pathExtension == "app" else { return }
                let due = await ReminderScheduler(center: UNUserNotificationCenter.current()).hrCapCheckDue()
                trailing = settingsRemindersTrailing(prefs, hrCapCheckOn: due != nil)
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
