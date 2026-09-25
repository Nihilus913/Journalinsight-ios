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
    /// W-B41 (B-41): which top-level Settings menu screen this section is pushed onto. The
    /// default derives it from the `sortKey` band, so a section file that has not been
    /// reassigned yet still compiles and lands somewhere sane; every shipped section overrides
    /// it with one explicit line.
    var group: SettingsGroupId { get }
    @ViewBuilder var body: Body { get }
}

public extension SettingsSection {
    var group: SettingsGroupId { SettingsGroupId(sortKey: sortKey) }
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

/// W-B41 (B-41) — the two-level Settings menu. One case per top-level row in `SettingsView`;
/// each pushes a `GroupSettingsView` rendering exactly the registry sections whose `group` is
/// this case. Toby 2026-09-22: "looks dumb, not enough sub menus" · "everything that pertains
/// to data sync" goes under Sync & hub. `SettingsGroup`/`SettingsSortKey` stay for the RN-era
/// band ordering (still the within-group order), they just no longer draw the screen.
// `nonisolated`: pure values, read from nonisolated tests.
public nonisolated enum SettingsGroupId: String, CaseIterable, Sendable, Equatable {
    case sync
    case widgets
    case home
    case kpis
    case haptics
    case health
    case about
    #if DEBUG
    /// DEBUG only — `ProviderSection`'s data-source switch must never ship to the phone.
    case developer
    #endif

    public var title: String {
        switch self {
        case .sync: "Sync & hub"
        case .widgets: "Widgets"
        case .home: "Home & Today layout"
        case .kpis: "KPIs & alerts"
        case .haptics: "Haptics & notifications"
        case .health: "Health access"
        case .about: "About & version"
        #if DEBUG
        case .developer: "Developer"
        #endif
        }
    }

    public var systemImage: String {
        switch self {
        case .sync: "arrow.triangle.2.circlepath"
        case .widgets: "square.grid.2x2"
        case .home: "house"
        case .kpis: "chart.bar"
        case .haptics: "bell"
        case .health: "heart"
        case .about: "info.circle"
        #if DEBUG
        case .developer: "hammer"
        #endif
        }
    }

    /// The row a group with no sections yet shows, so the menu shape is visible before the
    /// feature lands (rule 5: never a silently missing row).
    public var placeholder: String? {
        switch self {
        case .widgets: settingsWidgetsHowTo
        default: nil
        }
    }

    /// Fallback for a section that has not set `group` explicitly — the old RN bands.
    public init(sortKey: Int) {
        switch SettingsGroup(sortKey: sortKey) {
        case .connection: self = .sync
        case .preferences: self = .home
        case .data: self = .sync
        case .advanced: self = .about
        }
    }
}

/// W-FIX3 BUG-46: widgets shipped with B-34, so the Home & widgets footer says how to add one.
public nonisolated let settingsWidgetsHowTo = "To add a widget, touch and hold the Home Screen, tap Edit, then Add Widget and pick JournalInsight."

/// The ONE fixed array. Each later lane appends exactly one line (`<Area>Section()`); nothing
/// else in this file changes. `SettingsView` orders by `sortKey`, never by position here.
public enum SettingsRegistry {
    public static let sections: [any SettingsSection] = {
        var sections: [any SettingsSection] = [
        HubSection(),
        HealthSection(),
        PreferencesLinksSection(),
        DataLinksSection(),
        AppearanceSection(),
        RemindersSection(),
        EditTodaySection(),
        VersionSection(),
        DataQualitySection(),
        GateConfigSection(),
        LocalMirrorsSection(),
        WeeklyPlanSection(),
        ExportSection(),
        HapticsSection(),
        ]
        // W-B41: the data-source switch is a developer tool — it is not compiled into a Release
        // build at all, which is what keeps the `developer` group off Toby's phone.
        #if DEBUG
        sections.append(ProviderSection())
        #endif
        return sections
    }()
}
