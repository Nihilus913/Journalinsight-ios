import SwiftUI
import JIDesign

/// W-FIX11 H2-20: a Settings root row opened directly — More › Apple Health lands on the Apple Health
/// screen (the same `SettingsSectionsScreen` the Settings root pushes), not on the Settings list.
public nonisolated func settingsShortcutRow(_ id: String) -> SettingsRootRow? {
    SettingsRoot.rows.first { $0.id == id }
}

public struct SettingsRowShortcut: View {
    private let model: SettingsViewModel
    private let rowId: String
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel, rowId: String) { self.model = model; self.rowId = rowId }

    public var body: some View {
        NavigationStack {
            Group {
                if let row = settingsShortcutRow(rowId), case .push(let title, _, let placeholder) = row.kind {
                    SettingsSectionsScreen(title: title,
                                           sections: row.sectionIds.compactMap { id in model.sections.first { $0.id == id } },
                                           placeholder: placeholder)
                } else {
                    SettingsView(model: model)
                }
            }
            .environment(model)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    JIToolbarButton("checkmark", label: "Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .jiTheme(.native)
    }
}
