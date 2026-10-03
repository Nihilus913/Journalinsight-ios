import SwiftUI
import JICore
import JIDesign

/// W-B38-B B-10 — browse the one exercise catalogue grouped by targeted muscle, search by name,
/// muscle or equipment; a row opens the preview (symbol, muscles, equipment, cue — no animation,
/// Toby 2026-10-03) whose "Add to session" hands the exercise to the running strength log.
/// Native iOS 27 list + search (decision 1). Pushed inside the host's navigation stack.
public struct ExerciseLibraryView: View {
    @Bindable private var model: ExerciseLibraryViewModel
    private let canPick: Bool
    @Environment(\.dismiss) private var dismiss

    /// `canPick` false = browse only (no running session to add to).
    public init(model: ExerciseLibraryViewModel, canPick: Bool = true) {
        self.model = model
        self.canPick = canPick
    }

    public var body: some View {
        List {
            if model.groups.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
            ForEach(model.groups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        NavigationLink {
                            ExercisePreviewView(entry: entry, canPick: canPick) {
                                model.pick(entry)
                                dismiss()
                            }
                        } label: {
                            ExerciseLibraryRow(entry: entry)
                        }
                        .accessibilityIdentifier("exercise-library-row-\(entry.option.key)")
                    }
                }
            }
        }
        .searchable(text: $model.query, prompt: "Exercise, muscle or equipment")
        .navigationTitle("Exercises")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .jiTheme(.native)
    }
}

struct ExerciseLibraryRow: View {
    let entry: ExerciseLibraryEntry
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.option.key).font(.body)
                Text(entry.preview.muscleLine).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entry.preview.systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The exercise preview: what it trains, what it needs, one cue. Never an invented cue.
public struct ExercisePreviewView: View {
    let entry: ExerciseLibraryEntry
    let canPick: Bool
    let onPick: () -> Void

    public var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: entry.preview.systemImage)
                        .font(.system(size: 44)).frame(width: 64, height: 64)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.option.key).font(.title3.bold())
                        if let equipment = entry.preview.equipment {
                            Text(equipment).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Targets") {
                Text(entry.preview.muscleLine)
                    .accessibilityIdentifier("exercise-preview-muscles")
            }
            Section("Cue") {
                Text(entry.preview.cue ?? "No cue written for this exercise yet.")
                    .foregroundStyle(entry.preview.cue == nil ? .secondary : .primary)
            }
            if canPick {
                Section {
                    Button("Add to session", systemImage: "plus.circle.fill", action: onPick)
                        .accessibilityIdentifier("exercise-preview-add")
                }
            }
        }
        .navigationTitle(entry.option.key)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Exercise library") {
    NavigationStack { ExerciseLibraryView(model: ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known)) }
}
