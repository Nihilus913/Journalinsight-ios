import SwiftUI
import JIDesign

// W5a-L0 (P-settings seam). FROZEN after L0. The Settings screen is a section registry: this
// view only iterates `model.sections` (see `SettingsSection.swift`); every later lane adds its
// own `Sections/<Area>Section.swift` + one registry line and never touches this file.
// W-B41 (B-41): the screen is now the TOP LEVEL of a two-level menu — one `NavigationLink` per
// `SettingsGroupId`, each pushing a `GroupSettingsView` that renders that group's registry
// sections. Section bodies moved, never rewritten. Presented as a sheet from the `RootTabView`
// gear ("Done" = RN's `DoneButton`).
// B-57 W1 (fixer f3, board 5/01): the root is the board's FLAT list — CONNECTION · PREFERENCES ·
// DATA · ADVANCED. A registry section whose body is a single link row is drawn inline (its rows
// only, `settingsRowsOnly`); a section with its own fields (hub, Health, haptics, Edit Today…)
// sits behind one pushed row. `SettingsRoot.rows` is the one map, and a test pins that every
// registered section stays reachable from it.

/// One row (or run of inline rows) on the Settings root.
public nonisolated struct SettingsRootRow: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The sections' own link rows, drawn straight into the group's card.
        case inline
        /// One row that pushes a screen holding these sections.
        case push(title: String, systemImage: String, placeholder: String?)
    }
    public let id: String
    public let group: SettingsGroup
    public let kind: Kind
    public let sectionIds: [String]
}

public nonisolated enum SettingsRoot {
    public static let rows: [SettingsRootRow] = {
        var rows: [SettingsRootRow] = [
            .init(id: "hub", group: .connection, kind: .push(title: "Hub", systemImage: "server.rack", placeholder: nil),
                  sectionIds: ["l0.hub"]),
            .init(id: "health", group: .connection, kind: .push(title: "Apple Health", systemImage: "heart", placeholder: nil),
                  sectionIds: ["l0.health"]),
            .init(id: "preferences", group: .preferences, kind: .inline,
                  sectionIds: ["l0.preferences", "w5b.gateConfig", "l1.appearance", "l2.reminders"]),
            .init(id: "home", group: .preferences,
                  kind: .push(title: "Home & widgets", systemImage: "square.grid.2x2",
                              placeholder: SettingsGroupId.widgets.placeholder),
                  sectionIds: ["l3.editToday", "l5.weeklyPlan"]),
            .init(id: "haptics", group: .preferences,
                  kind: .push(title: "Haptics", systemImage: "iphone.radiowaves.left.and.right", placeholder: nil),
                  sectionIds: ["w8.haptics"]),
            .init(id: "data", group: .data, kind: .inline, sectionIds: settingsDataSectionIds),
            .init(id: "about", group: .advanced, kind: .inline, sectionIds: ["l4.version"]),
        ]
        #if DEBUG
        rows.append(.init(id: "developer", group: .advanced,
                          kind: .push(title: "Developer", systemImage: "hammer", placeholder: nil),
                          sectionIds: ["l3.provider"]))
        #endif
        return rows
    }()

    /// The board's four headers, in order.
    public static var headers: [String] { SettingsGroup.allCases.map(\.title) }
}

public struct SettingsView: View {
    @Environment(\.jiTheme) private var theme
    private let model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    Section {
                        ForEach(SettingsRoot.rows.filter { $0.group == group }) { row in
                            rootRow(row)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .data {
                            Text(settingsDataFooter).accessibilityIdentifier("settings.data.footer")
                        }
                    }
                }
            }
            .environment(model)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(theme.color(.info))
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .jiTheme(.native)
    }

    private func sections(_ ids: [String]) -> [any SettingsSection] {
        ids.compactMap { id in model.sections.first { $0.id == id } }
    }

    @ViewBuilder
    private func rootRow(_ row: SettingsRootRow) -> some View {
        switch row.kind {
        case .inline:
            ForEach(sections(row.sectionIds), id: \.id) { section in
                AnyView(section.body)
                    .environment(\.settingsRowsOnly, true)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
        case .push(let title, let systemImage, let placeholder):
            NavigationLink {
                SettingsSectionsScreen(title: title, sections: sections(row.sectionIds), placeholder: placeholder)
                    .environment(model)
            } label: {
                SettingsLinkLabel(title: title, subtitle: subtitle(for: row.id), systemImage: systemImage,
                                  trailing: trailing(for: row.id))
            }
            .accessibilityLabel(title)
            .accessibilityIdentifier("settings.root.\(row.id)")
        }
    }

    private func subtitle(for id: String) -> String {
        switch id {
        case "hub": URL(string: model.connection.baseURL)?.host().map { $0 } ?? "Not set up"
        case "health": "Backload and Apple Watch read access"
        case "home": "Edit Today, weekly plan, widgets"
        case "haptics": "Feel and notifications"
        case "developer": "Data source switch (debug builds only)"
        default: ""
        }
    }

    private func trailing(for id: String) -> String? {
        guard id == "hub", let status = model.connection.status else { return nil }
        if case .ok = status { return "Connected" }
        return "Not connected"
    }
}

/// A pushed Settings screen: the given registry sections, as `GroupSettingsView` draws them.
struct SettingsSectionsScreen: View {
    let title: String
    let sections: [any SettingsSection]
    var placeholder: String? = nil

    var body: some View {
        Form {
            ForEach(sections, id: \.id) { section in
                AnyView(section.body)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
            if let placeholder {
                Section { Text(placeholder).jiFont(.body, tint: .muted) }
            }
        }
        .navigationTitle(title)
        .jiTheme(.native)
    }
}

// MARK: - Built-in link rows (L0). Rows for screens that already exist (W3b KPIs, W4 goals-setup
// and backup). W5b screens (local mirrors, Health Connect, gate config) are NOT here — their
// lanes add their own sections.

/// RN row shape (bold title, muted subtitle, chevron) — B-33 §2b.2: the 44-pt `JIRow`. The
/// chevron comes from the enclosing `NavigationLink`, so the row never draws its own.
struct SettingsLinkLabel: View {
    let title: String
    let subtitle: String
    var systemImage: String? = nil
    /// B-57 W1: a row's state ("Locked", "Preparing…") sits trailing; the subtitle keeps saying
    /// what the row is for.
    var trailing: String? = nil
    var body: some View {
        JIRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            if let trailing { Text(trailing).jiFont(.subheadline, tint: .muted) }
        }
    }
}

/// RN "Preferences": Goals → `GoalsSetupView` (W4-L3), My KPIs → `KpiListView` (W3b-L2).
/// Edit Today (L3) and Appearance (L1) register their own sections in this band.
struct PreferencesLinksSection: SettingsSection {
    static let sectionId = "l0.preferences"
    let id = Self.sectionId
    let title = SettingsGroup.preferences.title
    let systemImage = "slider.horizontal.3"
    let sortKey = SettingsSortKey.preferences
    let group = SettingsGroupId.kpis
    var body: some View { PreferencesLinksRows() }
}

private struct PreferencesLinksRows: View {
    @Environment(SettingsViewModel.self) private var model
    var body: some View {
        SettingsRowGroup(header: SettingsGroup.preferences.title) {
            if let goals = model.goalsSetupModel {
                NavigationLink { GoalsSetupView(model: goals) } label: {
                    SettingsLinkLabel(title: "Goals", subtitle: "Weight, strength, steps, and nutrition targets", systemImage: "target")
                }
                .accessibilityLabel("Goals")
                .accessibilityIdentifier("settings.row.goals")
            } else {
                SettingsLinkLabel(title: "Goals", subtitle: "Connect to your hub to edit goals", systemImage: "target")
                    .accessibilityIdentifier("settings.row.goals.unavailable")
            }
            if let kpis = model.kpiListModel {
                NavigationLink { KpiListView(model: kpis) } label: {
                    SettingsLinkLabel(title: "My KPIs", subtitle: model.kpiSubtitle, systemImage: "chart.bar")
                }
                .accessibilityLabel("My KPIs")
                .accessibilityIdentifier("settings.row.kpis")
            } else {
                SettingsLinkLabel(title: "My KPIs", subtitle: "Connect to your hub to choose KPIs", systemImage: "chart.bar")
                    .accessibilityIdentifier("settings.row.kpis.unavailable")
            }
        }
    }
}

/// RN "Data": Backup & restore → `BackupView` (W4-L4). Local mirrors / Health Connect are W5b.
struct DataLinksSection: SettingsSection {
    static let sectionId = "l0.data"
    let id = Self.sectionId
    let title = SettingsGroup.data.title
    let systemImage = "externaldrive"
    let sortKey = SettingsSortKey.data
    let group = SettingsGroupId.sync
    var body: some View { DataLinksRows() }
}

private struct DataLinksRows: View {
    @Environment(SettingsViewModel.self) private var model
    var body: some View {
        SettingsRowGroup(header: SettingsGroup.data.title) {
            if let backup = model.backupModel {
                NavigationLink { BackupView(model: backup) } label: {
                    SettingsLinkLabel(title: "Backup & restore", subtitle: settingsDataSubtitles["Backup & restore"] ?? "",
                                      systemImage: "archivebox",
                                      trailing: backup.lastBackupAt?.formatted(.dateTime.day().month(.abbreviated)))
                }
                .accessibilityLabel("Backup & restore")
                .accessibilityIdentifier("settings.row.backup")
            } else {
                // Rule 5: never a silently missing row — the vault unlocks on the Journal tab.
                SettingsLinkLabel(title: "Backup & restore", subtitle: settingsDataSubtitles["Backup & restore"] ?? "",
                                  systemImage: "archivebox", trailing: "Locked")
                    .accessibilityHint("Open the Journal tab once to unlock the vault first")
                    .accessibilityIdentifier("settings.row.backup.unavailable")
            }
        }
    }
}
