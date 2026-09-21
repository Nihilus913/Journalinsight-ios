import SwiftUI
import JICore
import JIDesign

/// Create-or-edit form (oracle: `CreateChallengeForm` / `EditChallengeForm` in
/// `app/challenges.tsx`), driven by `ChallengeEditorViewModel`. Presented as a sheet from
/// `ChallengesView` for both "+ New challenge" and a card's "Edit" action.
public struct ChallengeEditor: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: ChallengeEditorViewModel
    let onSaved: (GateChallenge) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(model: ChallengeEditorViewModel, onSaved: @escaping (GateChallenge) -> Void) {
        self.model = model; self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Textbook intervals", text: $model.title)
                        .accessibilityLabel("Title")
                        .accessibilityIdentifier("challenge-editor-title")
                }
                Section("Hypothesis") {
                    TextField("What are you testing, and against what?", text: $model.hypothesis, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Hypothesis")
                        .accessibilityIdentifier("challenge-editor-hypothesis")
                }
                if model.canEditLockedFields {
                    Section("Target sessions") {
                        Stepper("\(model.targetSessions)", value: $model.targetSessions, in: 1...99)
                            .accessibilityLabel("Target sessions")
                            .accessibilityIdentifier("challenge-editor-target-sessions")
                    }
                    Section("Start date") {
                        TextField("YYYY-MM-DD", text: $model.startDate)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Start date")
                            .accessibilityIdentifier("challenge-editor-start-date")
                    }
                } else {
                    Text("Target sessions and start date are locked — archive it and create a new challenge instead to change those.")
                        .font(.caption).foregroundStyle(theme.color(.muted))
                }
                if model.isEditing {
                    Section("Result note") {
                        TextField("Optional", text: $model.resultNote, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityLabel("Result note")
                            .accessibilityIdentifier("challenge-editor-result-note")
                    }
                }
                // FROZEN CONTRACT — HR<=175 is a non-negotiable safety floor, not a challenge-
                // configurable rule (migration 032 has no column for it); shown fixed, never editable.
                Section {
                    Text("HR ≤ 175 always applies — not configurable").font(.caption.bold()).foregroundStyle(theme.color(.reduced))
                }
                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(theme.color(.danger))
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit challenge" : "New challenge")
            .jiNativeFormChrome()
            .jiTheme(.native)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityLabel("Cancel").accessibilityIdentifier("challenge-editor-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            if let saved = await model.submit() {
                                onSaved(saved)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSubmit)
                    .accessibilityLabel(model.isEditing ? "Save changes to \(model.title)" : "Save")
                    .accessibilityIdentifier("challenge-editor-save")
                }
            }
        }
    }
}
