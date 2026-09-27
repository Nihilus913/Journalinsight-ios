import SwiftUI
import JIDesign

/// Name · Dose · Time · Works for about — the Reminders "Medication" group rows (board
/// `5 Settings/08 Reminders`) plus one row the board lacks ("Works for about", needed for the
/// daytime-HRV window when Apple Health is not available). Used inline in Reminders and inside
/// `MedicationEditorSheet` (onboarding). Nothing is pre-filled: an unset time or duration
/// reads "—" plus a way to set it.
public struct MedicationFieldsSection: View {
    @Environment(\.jiTheme) private var theme
    @Binding private var entry: MedicationEntry
    public init(entry: Binding<MedicationEntry>) { _entry = entry }

    public var body: some View {
        Section {
            TextField("Name", text: $entry.name).accessibilityIdentifier("medication.name")
            TextField("Dose", text: $entry.dose).accessibilityIdentifier("medication.dose")
            timeRow
            hoursRow
        } header: {
            Text("Medication")
        } footer: {
            Text("You type it or pick it. Nothing is filled in for you.")
        }
    }

    private var timeText: String {
        entry.usualTime.map { ReminderScheduler.formatTime(hour: $0.hour, minute: $0.minute) } ?? "—"
    }

    @ViewBuilder private var timeRow: some View {
        if entry.usualTime != nil {
            Stepper {
                JIRow(title: "Time") { Text(timeText).jiFont(.subheadline, weight: .semibold).monospacedDigit() }
            } onIncrement: { shift(15) } onDecrement: { shift(-15) }
            .accessibilityLabel("Time")
            .accessibilityValue(timeText)
            .accessibilityIdentifier("medication.time")
        } else {
            JIRow(title: "Time") {
                HStack(spacing: 8) {
                    Text("— not set").jiFont(.subheadline, tint: .muted)
                    Button("Set time") { entry.usualTime = ReminderTime(hour: 8, minute: 0) }
                        .tint(theme.color(.info))
                }
            }
            .accessibilityIdentifier("medication.time")
        }
    }

    private var hoursRow: some View {
        let text = entry.worksForHours.map { "\($0) h" } ?? "— not set"
        return Stepper {
            JIRow(title: "Works for about") {
                Text(text).jiFont(.subheadline, weight: .semibold, tint: entry.worksForHours == nil ? .muted : nil).monospacedDigit()
            }
        } onIncrement: {
            entry.worksForHours = (entry.worksForHours ?? 0) + 1
        } onDecrement: {
            entry.worksForHours = entry.worksForHours.map { max(1, $0 - 1) }
        }
        .accessibilityLabel("Works for about")
        .accessibilityValue(text)
        .accessibilityIdentifier("medication.hours")
    }

    private func shift(_ minutes: Int) {
        guard let t = entry.usualTime else { return }
        let total = ReminderScheduler.wrapMinutesOfDay(t.hour * 60 + t.minute + minutes)
        entry.usualTime = ReminderTime(hour: total / 60, minute: total % 60)
    }
}

/// Onboarding "Add a medication" sheet: the same fields, Cancel / Save.
public struct MedicationEditorSheet: View {
    @State private var draft: MedicationEntry
    private let onSave: (MedicationEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    public init(entry: MedicationEntry, onSave: @escaping (MedicationEntry) -> Void) {
        _draft = State(initialValue: entry); self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form { MedicationFieldsSection(entry: $draft) }
                .jiNativeFormChrome()
                .scrollContentBackground(.hidden)
                .jiPageGround()
                .navigationTitle("Medication")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(draft); dismiss() }.disabled(!draft.isNamed)
                    }
                }
        }
        .jiTheme(.native)
    }
}
