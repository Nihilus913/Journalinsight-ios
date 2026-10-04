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

    /// B-107: the whole row is one tap target (a tap on the label or the switch flips it — before,
    /// only a swipe on the switch did in the sim). The switch is drawn, not hit-tested, so one tap
    /// never flips it twice.
    var body: some View {
        Button {
            let on = !model.paused
            Task { await model.set(paused: on) }
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("I'm on a break", systemImage: "pause.circle")
                        .foregroundStyle(.primary)
                    Text(model.sinceText ?? "Load reads Paused while this is on")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 8)
                Toggle("I'm on a break", isOn: .constant(model.paused))
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || model.state == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I'm on a break")
        .accessibilityValue(model.paused ? "On" : "Off")
        .accessibilityHint(model.sinceText ?? "Load reads Paused while this is on")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("settings.trainingBreak.toggle")
        .task { if model.state == nil { await model.load() } }
    }
}
