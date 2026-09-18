import SwiftUI
import JIDesign

// W5a-L2 — `mobile/app/reminders.tsx`: four daily reminder cards (toggle + hour/minute steppers +
// status line + notice) and the 7-row workout matrix. Pushed from `Settings/Sections/RemindersSection`.

public struct RemindersView: View {
    @State private var model: RemindersViewModel

    public init(model: RemindersViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            Section {
                Text(RemindersCopy.header).font(.footnote).foregroundStyle(JIColor.muted)
                if model.permissionDenied {
                    Text(RemindersCopy.permissionDenied)
                        .font(.footnote).foregroundStyle(JIColor.reduced)
                        .accessibilityIdentifier("reminders.notice.permissionDenied")
                }
            }
            ForEach(ReminderKind.allCases, id: \.self) { kind in
                DailyReminderSection(kind: kind, model: model)
            }
            WorkoutRemindersSection(model: model)
        }
        .navigationTitle("Reminders")
        .task { if !model.loaded { await model.load() } }
    }
}

private struct DailyReminderSection: View {
    let kind: ReminderKind
    let model: RemindersViewModel

    private var state: RemindersViewModel.DailyState? { model.daily[kind] }

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { state?.enabled ?? false },
                set: { next in Task { await model.setEnabled(kind, next) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.sectionTitle).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                    Text(kind.sectionCaption).font(.caption).foregroundStyle(JIColor.muted)
                }
            }
            .tint(JIColor.info)
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

            Text(model.statusLine(for: kind)).font(.caption).foregroundStyle(JIColor.muted)
                .accessibilityIdentifier("reminders.\(kind.rawValue).status")
            if let notice = state?.notice {
                Text(notice).font(.caption).foregroundStyle(JIColor.reduced)
                    .accessibilityIdentifier("reminders.\(kind.rawValue).notice")
            }
        }
    }
}

/// RN `Stepper`: "− 09 +" with `"<label> decrease"` / `"<label> increase"` a11y labels.
private struct StepperRow: View {
    let label: String
    let value: String
    let identifier: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(JIColor.text)
            Spacer()
            RoundStepButton(symbol: "minus", action: onDecrease)
                .accessibilityLabel("\(label) decrease")
                .accessibilityIdentifier("\(identifier).decrease")
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                .frame(minWidth: 44).monospacedDigit()
            RoundStepButton(symbol: "plus", action: onIncrease)
                .accessibilityLabel("\(label) increase")
                .accessibilityIdentifier("\(identifier).increase")
        }
    }
}

private struct RoundStepButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                .frame(width: 36, height: 36)
                .background(JIColor.surface2, in: Circle())
        }
        .buttonStyle(.pressableScale)
    }
}

private struct WorkoutRemindersSection: View {
    let model: RemindersViewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(RemindersCopy.workoutTitle).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                Text(RemindersCopy.workoutCaption).font(.caption).foregroundStyle(JIColor.muted)
            }
            ForEach(Weekday.displayOrder, id: \.self) { wd in
                let s = model.workouts[wd]
                HStack(spacing: 8) {
                    Text(wd.shortLabel).font(.subheadline).foregroundStyle(JIColor.text).frame(width: 40, alignment: .leading)
                    Toggle(isOn: Binding(
                        get: { s?.enabled ?? false },
                        set: { next in Task { await model.setWorkoutEnabled(wd, next) } }
                    )) { EmptyView() }
                    .labelsHidden()
                    .tint(JIColor.info)
                    .disabled(s?.busy ?? false)
                    .accessibilityLabel("\(wd.label) workout reminder")
                    .accessibilityIdentifier("reminders.workout.\(wd.rawValue).toggle")
                    Spacer()
                    RoundStepButton(symbol: "minus") { Task { await model.shiftWorkoutTime(wd, minutes: -RemindersViewModel.workoutStepMinutes) } }
                        .disabled(s?.busy ?? false)
                        .accessibilityLabel("\(wd.label) reminder time, earlier")
                        .accessibilityIdentifier("reminders.workout.\(wd.rawValue).earlier")
                    Text(model.workoutTimeLabel(wd)).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                        .frame(minWidth: 50).monospacedDigit()
                    RoundStepButton(symbol: "plus") { Task { await model.shiftWorkoutTime(wd, minutes: RemindersViewModel.workoutStepMinutes) } }
                        .disabled(s?.busy ?? false)
                        .accessibilityLabel("\(wd.label) reminder time, later")
                        .accessibilityIdentifier("reminders.workout.\(wd.rawValue).later")
                }
            }
            if let notice = model.workoutNotice {
                Text(notice).font(.caption).foregroundStyle(JIColor.reduced)
                    .accessibilityIdentifier("reminders.workout.notice")
            }
        }
    }
}
