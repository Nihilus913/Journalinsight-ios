#if canImport(WorkoutKit)
import SwiftUI
import JICore
import JIDesign

/// B-37-L3 (P-workouts) — Training "Send to Watch" sheet (spec §3 UI): the hub's cardio templates
/// with checkmarks (multi-select), a date picker (default today), and Send — disabled until
/// something is picked. Shows the scheduled names after a send, the error copy on failure, and
/// authorization-denied copy + a Settings button. Pure view over `SendToWatchViewModel`.
public struct SendToWatchSheet: View {
    @Bindable private var model: SendToWatchViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SendToWatchViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            List {
                templatesSection
                Section {
                    DatePicker("Date", selection: $model.date, displayedComponents: [.date])
                        .accessibilityLabel("Workout date")
                        .accessibilityIdentifier("send-to-watch-date")
                }
                statusSection
            }
            .navigationTitle("Send to Watch")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("send-to-watch-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await model.send() } }
                        .disabled(!model.canSend)
                        .accessibilityLabel("Send selected workouts to Watch")
                        .accessibilityIdentifier("send-to-watch-send")
                }
            }
            .task { if model.templates.isEmpty { await model.load() } }
        }
    }

    @ViewBuilder
    private var templatesSection: some View {
        Section {
            if model.state == .loading && model.templates.isEmpty {
                HStack { ProgressView(); Text("Loading templates…").foregroundStyle(JIColor.muted) }
                    .accessibilityIdentifier("send-to-watch-loading")
            } else if model.templates.isEmpty {
                Text("No workout templates on the hub.").foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("send-to-watch-empty")
            } else {
                ForEach(model.templates) { template in
                    Button { model.toggle(template.templateId) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.isSelected(template.templateId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.isSelected(template.templateId) ? JIColor.info : JIColor.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).foregroundStyle(JIColor.text)
                                Text(Self.summary(template)).font(.footnote).foregroundStyle(JIColor.muted)
                            }
                            Spacer()
                        }
                    }
                    .disabled(model.isBusy)
                    .accessibilityLabel(template.name)
                    .accessibilityValue(model.isSelected(template.templateId) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(model.isSelected(template.templateId) ? .isSelected : [])
                    .accessibilityIdentifier("send-to-watch-template-\(template.templateId)")
                }
            }
        } header: {
            Text("Workouts")
        } footer: {
            Text("Cardio only — strength stays in Bevel. Heart-rate alerts are absolute bpm, capped at 175.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case .idle, .loading:
            EmptyView()
        case .sending:
            Section {
                HStack { ProgressView(); Text(model.statusMessage).foregroundStyle(JIColor.muted) }
                    .accessibilityIdentifier("send-to-watch-sending")
            }
        case .sent:
            Section("Scheduled") {
                ForEach(model.sentNames, id: \.self) { name in
                    Label(name, systemImage: "checkmark.applewatch").foregroundStyle(JIColor.go)
                        .accessibilityIdentifier("send-to-watch-scheduled-row")
                }
                Text(model.statusMessage).font(.footnote).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("send-to-watch-status")
            }
        case .authDenied:
            Section {
                Text(model.statusMessage).font(.footnote).foregroundStyle(JIColor.danger)
                    .accessibilityIdentifier("send-to-watch-status")
                Button("Open Settings") { model.openSettings() }
                    .accessibilityLabel("Open Settings")
                    .accessibilityIdentifier("send-to-watch-open-settings")
            }
        case .error:
            Section {
                Text(model.statusMessage).font(.footnote).foregroundStyle(JIColor.danger)
                    .accessibilityIdentifier("send-to-watch-status")
                Button("Retry") { Task { if model.templates.isEmpty { await model.load() } else { await model.send() } } }
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("send-to-watch-retry")
            }
        }
    }

    /// "40 min · 3 steps" — total prescribed time and step count (interval pairs expanded).
    static func summary(_ t: WorkoutTemplate) -> String {
        let seconds = t.steps.reduce(0) { $0 + $1.seconds * max($1.repeat, 1) }
        let steps = t.steps.reduce(0) { $0 + max($1.repeat, 1) }
        return "\(seconds / 60) min · \(steps) step\(steps == 1 ? "" : "s")"
    }
}

extension EnvironmentValues {
    /// B-37-L3: set by the app's Training wiring (`RootTabView` → `.environment(\.sendToWatchModel, …)`);
    /// `nil` hides the toolbar button. Routed through the environment so `TrainingView.init(model:)`
    /// stays the frozen W3a contract — same idiom as `gateRationaleModel`.
    @Entry public var sendToWatchModel: SendToWatchViewModel?
}
#endif
