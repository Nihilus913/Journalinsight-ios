import SwiftUI
import JIDesign

// W5a-L2 — `mobile/app/reminders.tsx`: four daily reminder cards (toggle + hour/minute steppers +
// status line + notice) and the 7-row workout matrix. Pushed from `Settings/Sections/RemindersSection`.

public struct RemindersView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: RemindersViewModel

    public init(model: RemindersViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        List {
            Section {
                if model.permissionDenied {
                    Label(RemindersCopy.permissionDenied, systemImage: "bell.slash")
                        .foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("reminders.notice.permissionDenied")
                }
            } footer: {
                Text(RemindersCopy.header)
            }
            ForEach(ReminderKind.allCases, id: \.self) { kind in
                DailyReminderSection(kind: kind, model: model)
            }
            WorkoutRemindersSection(model: model)
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Reminders")
        .task { if !model.loaded { await model.load() } }
    }
}

private struct DailyReminderSection: View {
    @Environment(\.jiTheme) private var theme
    let kind: ReminderKind
    let model: RemindersViewModel

    private var state: RemindersViewModel.DailyState? { model.daily[kind] }

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { state?.enabled ?? false },
                set: { next in Task { await model.setEnabled(kind, next) } }
            )) {
                JIRow(title: kind.sectionTitle, subtitle: kind.sectionCaption)
            }
            .tint(theme.color(.info))
            .disabled(state?.busy ?? false)
            .accessibilityLabel(kind.sectionTitle)
            .accessibilityIdentifier("reminders.\(kind.rawValue).toggle")

            StepperRow(label: "Hour", value: String(format: "%02d", state?.time.hour ?? 0),
                       identifier: "reminders.\(kind.rawValue).hour",
                       onDecrease: { Task { await model.stepHour(kind, -1) } },
                       onIncrease: { Task { await model.stepHour(kind, 1) } })
            StepperRow(label: "Minute", value: String(format: "%02d", state?.time.minute ?? 0),
                       identifier: "reminders.\(kind.rawValue).minute",
                       onDecrease: { Task { await model.stepMinute(kind, -1) } },
                       onIncrease: { Task { await model.stepMinute(kind, 1) } })
        } header: {
            Text(kind.sectionTitle)
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusLine(for: kind))
                    .accessibilityIdentifier("reminders.\(kind.rawValue).status")
                if let notice = state?.notice {
                    Text(notice).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("reminders.\(kind.rawValue).notice")
                }
            }
        }
    }
}

/// RN `Stepper` ("− 09 +") — B-33 §2b.2: the system `Stepper`, so the ± targets, their
/// repeat-on-hold and their a11y actions all come from iOS. The identifiers stay on the
/// increment/decrement halves the RN tests knew.
private struct StepperRow: View {
    let label: String
    let value: String
    let identifier: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        Stepper {
            JIRow(title: label) { Text(value).jiFont(.subheadline, weight: .semibold).monospacedDigit() }
        } onIncrement: {
            onIncrease()
        } onDecrement: {
            onDecrease()
        }
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

private struct WorkoutRemindersSection: View {
    @Environment(\.jiTheme) private var theme
    let model: RemindersViewModel

    var body: some View {
        Section {
            // §8.1: the 7-row matrix stacks toggle over stepper instead of squeezing five
            // controls onto one line — it reflows at AX sizes rather than clipping.
            ForEach(Weekday.displayOrder, id: \.self) { wd in
                let s = model.workouts[wd]
                Toggle(isOn: Binding(
                    get: { s?.enabled ?? false },
                    set: { next in Task { await model.setWorkoutEnabled(wd, next) } }
                )) {
                    Text(wd.label).jiFont(.subheadline)
                }
                .tint(theme.color(.info))
                .disabled(s?.busy ?? false)
                .accessibilityLabel("\(wd.label) workout reminder")
                .accessibilityIdentifier("reminders.workout.\(wd.rawValue).toggle")

                Stepper {
                    JIRow(title: wd.shortLabel) {
                        Text(model.workoutTimeLabel(wd)).jiFont(.subheadline, weight: .semibold).monospacedDigit()
                    }
                } onIncrement: {
                    Task { await model.shiftWorkoutTime(wd, minutes: RemindersViewModel.workoutStepMinutes) }
                } onDecrement: {
                    Task { await model.shiftWorkoutTime(wd, minutes: -RemindersViewModel.workoutStepMinutes) }
                }
                .disabled(s?.busy ?? false)
                .accessibilityLabel("\(wd.label) reminder time")
                .accessibilityValue(model.workoutTimeLabel(wd))
                .accessibilityIdentifier("reminders.workout.\(wd.rawValue).time")
            }
        } header: {
            Text(RemindersCopy.workoutTitle)
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(RemindersCopy.workoutCaption)
                if let notice = model.workoutNotice {
                    Text(notice).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("reminders.workout.notice")
                }
            }
        }
    }
}
