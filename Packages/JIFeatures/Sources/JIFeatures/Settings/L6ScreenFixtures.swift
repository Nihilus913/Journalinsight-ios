import Foundation
import SwiftUI
import UserNotifications
import JICore
import JIHub
import JIDesign
import JIPersistence
import JIVault

// B-33 L6 — the fixture factories behind this lane's `ScreenRegistry` entries (§8.5). They live
// in an owned feature directory because `Gallery/` belongs to another lane; nothing here is
// reachable from the app, and every dependency is in-memory (one throwaway SQLite file per
// process, an in-memory secret store, a no-op notification centre), so the sweep never touches
// the Keychain, the hub or the user's database.
//
// Rule 5 holds here too: where a screen's content only arrives through an `async load()`, the
// entry renders that screen's own honest loading/empty state rather than fabricated rows.
enum L6Fixtures {
    // MARK: - In-memory plumbing

    /// One database for every entry; `AppDatabase.inMemory()` gives each call its own file, and a
    /// failure must not crash the sweep, so a failed open degrades to "no store".
    static let db: AppDatabase? = try? AppDatabase.inMemory()

    static let today = Date(timeIntervalSince1970: 1_789_992_000) // 2026-09-21 12:00 UTC

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    /// Seeded once: a handful of goals so the Goals screen renders rows, not its empty state.
    static let seededGoalStore: GoalStore? = {
        guard let db else { return nil }
        let store = GoalStore(db: db)
        try? store.addGoal(NewGoal(title: "Bench 100 kg", targetDate: "2026-12-31", progress: 0.4), now: today)
        try? store.addGoal(NewGoal(title: "15 000 steps daily", targetDate: nil, progress: 0.8), now: today)
        return store
    }()

    static var prefStore: PrefStore? { db.map { PrefStore(db: $0) } }

    static let provider = MockDataProvider()

    /// An in-memory `SecretStore`: the connection sheet reads its store in `init`, and the sweep
    /// must never reach the real Keychain.
    nonisolated final class MemorySecrets: SecretStore, @unchecked Sendable {
        // @unchecked: a fixture-only store touched from the MainActor render path alone.
        private var items: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { items[key] }
        func write(_ key: String, _ data: Data) throws { items[key] = data }
        func delete(_ key: String) throws { items[key] = nil }
    }

    static let connectionStore = ConnectionConfigStore(secrets: MemorySecrets())

    /// A notification centre that schedules nothing — `RemindersViewModel` only reads it in its
    /// `async load()`, which the renderer never runs.
    final class SilentCenter: ReminderNotificationCenter {
        func pendingRequests() async -> [UNNotificationRequest] { [] }
        func add(_ request: UNNotificationRequest) async throws {}
        func removePendingRequests(withIdentifiers identifiers: [String]) {}
        func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
        func requestAuthorization() async throws -> Bool { true }
    }

    // MARK: - Screens

    static func journal() -> AnyView {
        guard let db else { return unavailable("Journal") }
        return AnyView(JournalView(model: JournalViewModel(db: db, vault: VaultManager(keychain: SecureKeychainService()), now: { today })))
    }

    static func journalCalendar() -> AnyView {
        AnyView(
            ScrollView {
                CalendarView(
                    scope: .month, anchor: today,
                    entryDates: ["2026-09-18", "2026-09-19", "2026-09-21"],
                    onSelectDay: { _ in }, onShift: { _ in }
                )
                .padding(16)
                .readableColumn()
            }
        )
    }

    static func journalEntry() -> AnyView {
        AnyView(EntrySheet(model: EntrySheetViewModel(today: today), onSave: {}, onCancel: {}))
    }

    static func mindModel() -> MindViewModel? {
        guard let db else { return nil }
        return MindViewModel(
            checkins: CheckInStore(db: db), eventStore: EventStore(db: db), who5Store: Who5Store(db: db),
            now: { today }
        )
    }

    static func mind() -> AnyView {
        guard let model = mindModel() else { return unavailable("Mind") }
        return AnyView(MindView(model: model))
    }

    static func mindCheckIn() -> AnyView {
        guard let model = mindModel() else { return unavailable("Mind check-in") }
        return AnyView(CheckInSheet(model: model))
    }

    static func mindEvent() -> AnyView {
        guard let model = mindModel() else { return unavailable("Mind event") }
        return AnyView(EventSheet(model: model))
    }

    static func who5() -> AnyView {
        guard let model = mindModel() else { return unavailable("WHO-5") }
        return AnyView(Who5Sheet(model: model))
    }

    static func challengesModel() -> ChallengesViewModel {
        ChallengesViewModel(provider: provider, now: { today })
    }

    static func challenges() -> AnyView {
        AnyView(NavigationStack { ChallengesView(model: challengesModel()) })
    }

    static func challengeEditor() -> AnyView {
        AnyView(ChallengeEditor(model: ChallengeEditorViewModel(challenges: challengesModel(), now: { today }), onSaved: { _ in }))
    }

    static func goals() -> AnyView {
        guard let store = seededGoalStore else { return unavailable("Goals") }
        return AnyView(NavigationStack { GoalsView(model: GoalsViewModel(store: store), now: { today }) })
    }

    static func goalsSetup() -> AnyView {
        AnyView(NavigationStack {
            GoalsSetupView(model: GoalsSetupViewModel(provider: provider, goalStore: seededGoalStore, now: { today }))
        })
    }

    static func settings() -> AnyView {
        guard let prefs = prefStore else { return unavailable("Settings") }
        return AnyView(SettingsView(model: SettingsViewModel(store: connectionStore, prefs: prefs, onSaved: { _ in })))
    }

    /// W-B41 (B-41): one fixture per top-level Settings group screen, so the sweep covers the
    /// new second level and not just the menu. Same in-memory model as `settings()`; the DEBUG
    /// `developer` group is deliberately NOT registered in the sweep (it never ships).
    static func settingsGroup(_ group: SettingsGroupId) -> AnyView {
        guard let prefs = prefStore else { return unavailable("Settings \(group.title)") }
        let model = SettingsViewModel(store: connectionStore, prefs: prefs, onSaved: { _ in })
        return AnyView(NavigationStack {
            GroupSettingsView(group: group, sections: model.sections).environment(model)
        })
    }

    static func settingsSync() -> AnyView { settingsGroup(.sync) }
    static func settingsWidgets() -> AnyView { settingsGroup(.widgets) }
    static func settingsHome() -> AnyView { settingsGroup(.home) }
    static func settingsKpis() -> AnyView { settingsGroup(.kpis) }
    static func settingsHaptics() -> AnyView { settingsGroup(.haptics) }
    static func settingsHealth() -> AnyView { settingsGroup(.health) }
    static func settingsAbout() -> AnyView { settingsGroup(.about) }

    static func hubConnection() -> AnyView {
        AnyView(ConnectionSheet(store: connectionStore, onSaved: { _ in }))
    }

    static func appearance() -> AnyView {
        guard let prefs = prefStore else { return unavailable("Appearance") }
        return AnyView(NavigationStack { AppearanceView(model: AppearanceViewModel(prefs: prefs, hour: { 9 })) })
    }

    static func backup() -> AnyView {
        guard let db else { return unavailable("Backup") }
        return AnyView(NavigationStack { BackupView(model: BackupViewModel(db: db, cipher: IdentityCipher(), appVersion: "1.0.0")) })
    }

    static func export() -> AnyView {
        guard let db else { return unavailable("Export") }
        let model = ExportViewModel(stores: .init(
            journal: JournalStore(db: db), checkins: CheckInStore(db: db), events: EventStore(db: db),
            who5: Who5Store(db: db), goals: seededGoalStore
        ))
        model.load() // synchronous — the counts are real, not a spinner
        return AnyView(NavigationStack { ExportView(model: model) })
    }

    static func version() -> AnyView {
        guard let prefs = prefStore else { return unavailable("Version") }
        return AnyView(NavigationStack {
            VersionView(model: VersionViewModel(
                prefs: prefs,
                info: VersionInfo(appName: "JournalInsight", appVersion: "1.0.0", build: "42", bundleId: "toby913.JournalInsight")
            ))
        })
    }

    static func localMirrors() -> AnyView {
        guard let db else { return unavailable("Local mirrors") }
        return AnyView(NavigationStack {
            LocalMirrorsView(model: LocalMirrorsViewModel(
                goalStore: seededGoalStore,
                challengesModel: challengesModel(),
                decisionLog: DecisionLogStore(db: db)
            ))
        })
    }

    static func dataQuality() -> AnyView {
        AnyView(NavigationStack { DataQualityView(model: DataQualityViewModel(provider: provider)) })
    }

    static func reminders() -> AnyView {
        guard let prefs = prefStore else { return unavailable("Reminders") }
        return AnyView(NavigationStack {
            RemindersView(model: RemindersViewModel(
                scheduler: ReminderScheduler(center: SilentCenter()), prefs: prefs, today: { "2026-09-21" }
            ))
        })
    }

    static func healthPermission() -> AnyView {
        AnyView(NavigationStack {
            List {
                Section("Apple Watch (read)") {
                    HealthPermissionView(model: HealthPermissionViewModel(permission: .notDetermined, requestPermission: { .notDetermined }))
                }
            }
            .jiNativeFormChrome()
            .jiTheme(.native)
            .navigationTitle("Health permission")
        })
    }

    /// Rule 5: a fixture that could not be built says so instead of rendering a blank frame.
    private static func unavailable(_ name: String) -> AnyView {
        AnyView(
            ContentUnavailableView("\(name) fixture unavailable", systemImage: "exclamationmark.triangle")
                .jiTheme(.native)
        )
    }
}
