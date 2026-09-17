import SwiftUI

// W5a-L0 (P-settings seam). FROZEN after L0: the ONLY permitted edit in this file is appending
// one line to `SettingsRegistry.sections` (one per lane, its own `Sections/<Area>Section.swift`).

/// One block of the Settings screen. `body` is placed directly inside `SettingsView`'s `Form`,
/// so it is one or more `Section { … }`s (never bare rows) — a section that needs the screen's
/// models reads `@Environment(SettingsViewModel.self)` from a small `View` of its own (see
/// `Sections/HubSection.swift` for the idiom; a protocol conformer isn't a `View` and can't
/// carry `@Environment` itself). `title`/`systemImage` are the registry's metadata (the
/// accessibility identifier `settings.section.<id>` and future search/jump lists), not a header
/// `SettingsView` draws — each `Section` names itself, exactly like RN's `SectionLabel`s.
public protocol SettingsSection {
    associatedtype Body: View
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    /// Position in the screen. Use the `SettingsSortKey` bands so a lane's section lands in the
    /// RN group it belongs to (Connection → Preferences → Data → Advanced, `settings.tsx`).
    var sortKey: Int { get }
    @ViewBuilder var body: Body { get }
}

/// RN `settings.tsx` groups (its four `SectionLabel`s). A `sortKey` picks the band; within a
/// band, lower keys render first. Built-in L0 sections sit at the band's base value.
// `nonisolated`: pure values, usable from nonisolated tests/lanes (JIFeatures' default isolation is MainActor).
public nonisolated enum SettingsSortKey {
    public static let connection = 0     // hub fields, Apple Health backload, Apple Watch read
    public static let preferences = 100  // Goals, Edit Today (L3), My KPIs, Appearance (L1)
    public static let data = 200         // Backup & restore, Reminders (L2)
    public static let advanced = 300     // About & version (L4)
}

public nonisolated enum SettingsGroup: String, CaseIterable, Sendable, Equatable {
    case connection, preferences, data, advanced

    public init(sortKey: Int) {
        switch sortKey {
        case ..<SettingsSortKey.preferences: self = .connection
        case ..<SettingsSortKey.data: self = .preferences
        case ..<SettingsSortKey.advanced: self = .data
        default: self = .advanced
        }
    }

    /// Verbatim `SectionLabel` copy from `settings.tsx`.
    public var title: String {
        switch self {
        case .connection: "Connection"
        case .preferences: "Preferences"
        case .data: "Data"
        case .advanced: "Advanced"
        }
    }
}

/// The ONE fixed array. Each later lane appends exactly one line (`<Area>Section()`); nothing
/// else in this file changes. `SettingsView` orders by `sortKey`, never by position here.
public enum SettingsRegistry {
    public static let sections: [any SettingsSection] = [
        HubSection(),
        HealthSection(),
        PreferencesLinksSection(),
        DataLinksSection(),
        AppearanceSection(),
    ]
}
