import SwiftUI
import JIDesign

// W5a-L0 (P-settings seam). FROZEN after L0. The Settings screen is a section registry: this
// view only iterates `model.sections` (see `SettingsSection.swift`); every later lane adds its
// own `Sections/<Area>Section.swift` + one registry line and never touches this file.
// W-B41 (B-41): the screen is now the TOP LEVEL of a two-level menu — one `NavigationLink` per
// `SettingsGroupId`, each pushing a `GroupSettingsView` that renders that group's registry
// sections. Section bodies moved, never rewritten. Presented as a sheet from the `RootTabView`
// gear ("Done" = RN's `DoneButton`).
public struct SettingsView: View {
    @Environment(\.jiTheme) private var theme
    private let model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmptyView()
                } footer: {
                    Text("Connect to your HealthTraining hub to replace the built-in sample data.")
                }
                ForEach(SettingsGroupId.allCases, id: \.rawValue) { group in
                    NavigationLink {
                        GroupSettingsView(group: group, sections: model.sections)
                            .environment(model)
                    } label: {
                        Label(group.title, systemImage: group.systemImage)
                    }
                    .accessibilityLabel(group.title)
                    .accessibilityIdentifier("settings.group.\(group.rawValue)")
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
        Section(SettingsGroup.preferences.title) {
            if let goals = model.goalsSetupModel {
                NavigationLink { GoalsSetupView(model: goals) } label: {
                    SettingsLinkLabel(title: "Goals", subtitle: "Weight, strength, steps, and nutrition targets")
                }
                .accessibilityLabel("Goals")
                .accessibilityIdentifier("settings.row.goals")
            } else {
                SettingsLinkLabel(title: "Goals", subtitle: "Connect to your hub to edit goals")
                    .accessibilityIdentifier("settings.row.goals.unavailable")
            }
            if let kpis = model.kpiListModel {
                NavigationLink { KpiListView(model: kpis) } label: {
                    SettingsLinkLabel(title: "My KPIs", subtitle: model.kpiSubtitle)
                }
                .accessibilityLabel("My KPIs")
                .accessibilityIdentifier("settings.row.kpis")
            } else {
                SettingsLinkLabel(title: "My KPIs", subtitle: "Connect to your hub to choose KPIs")
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
                                      systemImage: "archivebox")
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
