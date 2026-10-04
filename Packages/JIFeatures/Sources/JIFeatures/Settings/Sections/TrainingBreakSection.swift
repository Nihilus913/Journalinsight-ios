import SwiftUI
import JIDesign

// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status"): Settings › Today — the user's
// "I'm on a break" toggle. While on, Decide's Load row reads "Paused" + the start date.
public struct TrainingBreakSection: SettingsSection {
    public nonisolated static let sectionId = "b91.trainingBreak"
    public let id = Self.sectionId
    public let title = "Training break"
    public let systemImage = "pause.circle"
    public let sortKey = SettingsSortKey.preferences + 5
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { TrainingBreakRows() }
}

private struct TrainingBreakRows: View {
    @Environment(SettingsViewModel.self) private var settings
    var body: some View {
        if let model = settings.trainingBreakModel { TrainingBreakToggle(model: model) }
    }
}

struct TrainingBreakToggle: View {
    let model: TrainingBreakViewModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.paused }, set: { on in Task { await model.set(paused: on) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Label("I'm on a break", systemImage: "pause.circle")
                Text(model.sinceText ?? "Load reads Paused while this is on")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .disabled(model.busy || model.state == nil)
        .accessibilityIdentifier("settings.trainingBreak.toggle")
        .task { if model.state == nil { await model.load() } }
    }
}
