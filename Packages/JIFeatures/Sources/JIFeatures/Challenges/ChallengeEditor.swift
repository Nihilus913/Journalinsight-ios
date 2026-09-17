import SwiftUI
import JICore
import JIDesign

/// Create-or-edit form (oracle: `CreateChallengeForm` / `EditChallengeForm` in
/// `app/challenges.tsx`), driven by `ChallengeEditorViewModel`. Presented as a sheet from
/// `ChallengesView` for both "+ New challenge" and a card's "Edit" action.
public struct ChallengeEditor: View {
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
                }
                Section("Hypothesis") {
                    TextField("What are you testing, and against what?", text: $model.hypothesis, axis: .vertical)
                        .lineLimit(3...6)
                }
                if model.canEditLockedFields {
                    Section("Target sessions") {
                        Stepper("\(model.targetSessions)", value: $model.targetSessions, in: 1...99)
                    }
                    Section("Start date") {
                        TextField("YYYY-MM-DD", text: $model.startDate)
                            .autocorrectionDisabled()
                    }
                } else {
                    Text("Target sessions and start date are locked — archive it and create a new challenge instead to change those.")
                        .font(.caption).foregroundStyle(JIColor.muted)
                }
                if model.isEditing {
                    Section("Result note") {
                        TextField("Optional", text: $model.resultNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                // FROZEN CONTRACT — HR<=175 is a non-negotiable safety floor, not a challenge-
                // configurable rule (migration 032 has no column for it); shown fixed, never editable.
                Section {
                    Text("HR ≤ 175 always applies — not configurable").font(.caption.bold()).foregroundStyle(JIColor.reduced)
                }
                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(JIColor.danger)
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit challenge" : "New challenge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                }
            }
        }
    }
}
