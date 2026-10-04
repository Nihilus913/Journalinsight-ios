import SwiftUI
import JIDesign

/// B-43 P2: the TRAINING card on Reminders — "Planned session" (toggle + ±15 min time, off until
/// toggled, 17:30) and "Session left open" (toggle, on by default; fires 90 min after the last set).
struct TrainingNudgesSection: View {
    @Environment(\.jiTheme) private var theme
    let model: RemindersViewModel

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.trainingNudges.workoutDayEnabled },
                set: { next in Task { await model.setWorkoutDayEnabled(next) } }
            )) {
                JIRow(title: ReminderKind.workoutDay.boardTitle, subtitle: "Planned days · \(model.workoutDayTimeLabel)",
                      systemImage: ReminderKind.workoutDay.boardSymbol)
            }
            .tint(theme.color(.info))
            .accessibilityLabel(ReminderKind.workoutDay.sectionTitle)
            .accessibilityValue("\(model.trainingNudges.workoutDayEnabled ? "On" : "Off"), \(model.workoutDayTimeLabel). \(model.workoutDayStatusLine)")
            .accessibilityIdentifier("reminders.workoutDay.toggle")

            Stepper {
                JIRow(title: "Time") {
                    Text(model.workoutDayTimeLabel).jiFont(.subheadline, weight: .semibold).monospacedDigit()
                }
            } onIncrement: {
                Task { await model.shiftWorkoutDayTime(minutes: RemindersViewModel.workoutStepMinutes) }
            } onDecrement: {
                Task { await model.shiftWorkoutDayTime(minutes: -RemindersViewModel.workoutStepMinutes) }
            }
            .accessibilityLabel("Planned session time")
            .accessibilityValue(model.workoutDayTimeLabel)
            .accessibilityIdentifier("reminders.workoutDay.time")

            Toggle(isOn: Binding(
                get: { model.trainingNudges.sessionOpenEnabled },
                set: { next in Task { await model.setSessionOpenEnabled(next) } }
            )) {
                JIRow(title: ReminderKind.sessionOpen.boardTitle, subtitle: "90 min after the last set",
                      systemImage: ReminderKind.sessionOpen.boardSymbol)
            }
            .tint(theme.color(.info))
            .accessibilityLabel(ReminderKind.sessionOpen.sectionTitle)
            .accessibilityValue(model.trainingNudges.sessionOpenEnabled ? "On" : "Off")
            .accessibilityIdentifier("reminders.sessionOpen.toggle")
        } header: {
            Text("Training")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ReminderKind.workoutDay.sectionCaption)
                Text(model.workoutDayStatusLine).accessibilityIdentifier("reminders.workoutDay.status")
                if let notice = model.trainingNotice {
                    Text(notice).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("reminders.training.notice")
                }
            }
        }
    }
}
