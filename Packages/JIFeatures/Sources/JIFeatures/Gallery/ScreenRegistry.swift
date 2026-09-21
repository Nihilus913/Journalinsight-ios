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

        // MARK: L4 — chrome + hero screens (append-only; never reorder another lane's block)
        ScreenEntry(name: "Today") { L4Screens.today() },
    ]
}
