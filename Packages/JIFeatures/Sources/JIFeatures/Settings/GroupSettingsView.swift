import SwiftUI
import JIDesign

// W-B41 (B-41, P-settings). The second level of the Settings menu: one generic screen per
// `SettingsGroupId`, rendering the registry sections assigned to that group in `sortKey` order.
// It draws nothing of its own — the section bodies are the SAME `Section { … }`s the flat
// screen used to show, moved here unchanged (their `settings.section.<id>` identifier included).
// A group with no sections yet still gets a row at the top level and says so here (rule 5).

/// B-57 W1: the DATA rows' footer and subtitles (board `5 Settings`). The DATA rows live in the
/// `.sync` group ("Sync & hub"), so the footer is drawn there.
public nonisolated let settingsDataFooter = "Backup is for restoring. Export is for reading elsewhere. The other two show where your numbers come from."
public nonisolated let settingsDataSubtitles: [String: String] = [
    "Backup & restore": "Full copy of Journal and Mind, to restore on a new phone",
    "Export": "A readable CSV or JSON of what you pick",
    "Local data mirrors": "Copies kept here so screens work away from home",
    "Data quality": "Which sources are fresh and trusted",
]
public struct GroupSettingsView: View {
    private let group: SettingsGroupId
    private let sections: [any SettingsSection]

    /// `sections` defaults to the registry; `SettingsView` passes its model's already-sorted
    /// list so a test (or a preview) can drive the screen with its own sections.
    public init(group: SettingsGroupId, sections: [any SettingsSection] = SettingsRegistry.sections) {
        self.group = group
        self.sections = Self.sections(in: group, from: sections)
    }

    /// The one filter rule, exposed so the coverage tests assert exactly what the screen renders.
    public static func sections(in group: SettingsGroupId,
                                from all: [any SettingsSection] = SettingsRegistry.sections) -> [any SettingsSection] {
        all.filter { $0.group == group }.sorted { $0.sortKey < $1.sortKey }
    }

    public var body: some View {
        Form {
            if sections.isEmpty {
                Section {
                    Text(group.placeholder ?? "Nothing here yet.")
                        .jiFont(.body, tint: .muted)
                        .disabled(true)
                        .accessibilityIdentifier("settings.group.\(group.rawValue).empty")
                }
            }
            ForEach(sections, id: \.id) { section in
                AnyView(section.body)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
            if group == .sync {
                Section { } footer: {
                    Text(settingsDataFooter).accessibilityIdentifier("settings.data.footer")
                }
            }
        }
        .navigationTitle(group.title)
        .jiTheme(.native)
    }
}
