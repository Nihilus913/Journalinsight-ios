import SwiftUI
import JIDesign

/// §8.5 one line per screen that ships in the native language. The sweep test renders every
/// entry in every `SweepMatrix` cell; HT `tests/test_theme_status_ledger.py` checks each name
/// is in `docs/THEME_STATUS.md`. Adding a screen = one entry here + one ledger row.
public nonisolated struct ScreenEntry: Sendable, Identifiable {
    public let name: String
    public let theme: JITheme
    public let make: @MainActor @Sendable () -> AnyView
    public var id: String { name }
    public var slug: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }
    public init(name: String, theme: JITheme = .native, make: @escaping @MainActor @Sendable () -> AnyView) {
        self.name = name; self.theme = theme; self.make = make
    }
}

/// `nonisolated`: the list is read from nonisolated tests; `make` itself is MainActor.
public nonisolated enum ScreenRegistry {
    public static let entries: [ScreenEntry] = [
        ScreenEntry(name: "Native gallery") { AnyView(NativeGalleryView()) },

        // MARK: L6 — Journal · Mind · Coach · Settings & Data (B-33 Phase B). Append-only.
        ScreenEntry(name: "Journal") { L6Fixtures.journal() },
        ScreenEntry(name: "Journal calendar") { L6Fixtures.journalCalendar() },
        ScreenEntry(name: "Journal entry") { L6Fixtures.journalEntry() },
        ScreenEntry(name: "Mind") { L6Fixtures.mind() },
        ScreenEntry(name: "Mind check-in") { L6Fixtures.mindCheckIn() },
        ScreenEntry(name: "Mind event") { L6Fixtures.mindEvent() },
        ScreenEntry(name: "WHO-5") { L6Fixtures.who5() },
        ScreenEntry(name: "Challenges") { L6Fixtures.challenges() },
        ScreenEntry(name: "Challenge editor") { L6Fixtures.challengeEditor() },
        ScreenEntry(name: "Goals") { L6Fixtures.goals() },
        ScreenEntry(name: "Goals setup") { L6Fixtures.goalsSetup() },
        ScreenEntry(name: "Settings") { L6Fixtures.settings() },
        ScreenEntry(name: "Hub connection") { L6Fixtures.hubConnection() },
        ScreenEntry(name: "Appearance") { L6Fixtures.appearance() },
        ScreenEntry(name: "Backup") { L6Fixtures.backup() },
        ScreenEntry(name: "Export") { L6Fixtures.export() },
        ScreenEntry(name: "Version") { L6Fixtures.version() },
        ScreenEntry(name: "Local mirrors") { L6Fixtures.localMirrors() },
        ScreenEntry(name: "Data quality") { L6Fixtures.dataQuality() },
        ScreenEntry(name: "Reminders") { L6Fixtures.reminders() },
        ScreenEntry(name: "Health permission") { L6Fixtures.healthPermission() },
    ]
}
