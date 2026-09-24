import SwiftUI
import JIPersistence

// W5b-L4 (P-local-mirrors). RN `settings.tsx:606` Data card "Local data mirrors" →
// `router.push("/local-mirrors")`; sits after Backup & restore / Reminders in the Data band.
public struct LocalMirrorsSection: SettingsSection {
    public static let sectionId = "w5b.l4.localMirrors"
    public let id = Self.sectionId
    public let title = "Local data mirrors"
    public let systemImage = "internaldrive"
    public let sortKey = SettingsSortKey.data + 20
    public let group = SettingsGroupId.sync
    public init() {}
    public var body: some View { LocalMirrorsSectionRows() }
}

/// One shared on-device pool for this entry point. `SettingsViewModel` (frozen, W5a-L0) carries
/// no database handle, so — like `RemindersSection` building its own `UNUserNotificationCenter`
/// — the section opens the app's `journalinsight.sqlite` itself, once (`static let`), rather than
/// a new pool per navigation. nil = the file couldn't be opened; the screen then says so per
/// section (rule 5) instead of crashing.
private nonisolated enum LocalMirrorsDatabase {
    static let db: AppDatabase? = try? AppDatabase.onDisk()
    static let decisionLog: DecisionLogStore? = db.map(DecisionLogStore.init(db:))
    static let goalStore: GoalStore? = db.map(GoalStore.init(db:))
}

private struct LocalMirrorsSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Section {
            NavigationLink {
                LocalMirrorsView(model: LocalMirrorsViewModel(
                    goals: model.goalsSetupModel?.goals,
                    goalStore: LocalMirrorsDatabase.goalStore,
                    targets: model.kpiListModel?.targets ?? [],
                    decisionLog: LocalMirrorsDatabase.decisionLog
                ))
            } label: {
                SettingsLinkLabel(title: "Local data mirrors", subtitle: settingsDataSubtitles["Local data mirrors"] ?? "")
            }
            .accessibilityLabel("Local data mirrors")
            .accessibilityIdentifier("settings.row.localMirrors")
        }
    }
}
