import SwiftUI
import SwiftData

struct ManualWorkoutLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = .now
    @State private var durationMin: Double = 45
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Workout date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("Duration") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(durationMin)) minutes")
                            .font(.headline)
                        Slider(value: $durationMin, in: 5...180, step: 5)
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let entry = WorkoutEntry(
            date: selectedDate,
            source: .manual,
            durationSec: Int(durationMin * 60),
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(entry)
        dismiss()
    }
}

#Preview {
    ManualWorkoutLogSheet()
        .modelContainer(for: WorkoutEntry.self, inMemory: true)
}
