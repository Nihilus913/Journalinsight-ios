import SwiftUI
import JIDesign

/// Add/edit-entry sheet (oracle: `EntrySheet.tsx`). `onSave` is handed the finished `NewEntry`
/// write closure from `JournalViewModel` so this view never touches `JournalStore` directly.
public struct EntrySheet: View {
    @Bindable var model: EntrySheetViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    public init(model: EntrySheetViewModel, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Mood") {
                    MoodPicker(selection: $model.mood)
                }
                Section("Entry") {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Entry text")
                }
                Section("Tags") {
                    ForEach(model.tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button("Remove") { model.removeTag(tag) }
                        }
                    }
                    HStack {
                        TextField("Add tag", text: $model.tagDraft)
                            .onSubmit { model.addTagFromDraft() }
                        Button("Add") { model.addTagFromDraft() }
                    }
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(JIColor.danger)
                }
            }
            .navigationTitle(model.editingId == nil ? "New Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(!model.canSave || model.isSaving)
                }
            }
        }
    }
}
