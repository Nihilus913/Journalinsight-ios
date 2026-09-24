import SwiftUI
import JIDesign

// W5a-L2 — `mobile/app/reminders.tsx`: four daily reminder cards (toggle + hour/minute steppers +
// status line + notice) and the 7-row workout matrix. Pushed from `Settings/Sections/RemindersSection`.

/// B-57 W1 board 5/08 (layout only — the medication fields and the HR-cap check are W4): a
/// DAILY card of toggle rows ("Daily · 21:00"), a WORKOUT DAYS card (day · time · toggle), and an
/// EDIT TIME card whose steppers edit the reminder picked in it.
public struct RemindersView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: RemindersViewModel
    @State private var editing: ReminderEditTarget = .daily(.journal)

    public init(model: RemindersViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        List {
            if model.permissionDenied {
                Section {
                    Label(RemindersCopy.permissionDenied, systemImage: "bell.slash")
                        .foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("reminders.notice.permissionDenied")
                }
            }
            Section {
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    DailyReminderRow(kind: kind, model: model)
                }
            } header: {
                Text("Daily")
            } footer: {
                let notices = ReminderKind.allCases.compactMap { model.daily[$0]?.notice }
                if !notices.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(notices, id: \.self) { Text($0).foregroundStyle(theme.color(.reduced)) }
                    }
                }
            }
            WorkoutRemindersSection(model: model)
            EditTimeSection(model: model, editing: $editing)
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Reminders")
        .navigationSubtitle(RemindersCopy.header)
        .task { if !model.loaded { await model.load() } }
    }
}

/// Which reminder the EDIT TIME card is editing.
enum ReminderEditTarget: Hashable {
    case daily(ReminderKind)
    case workout(Weekday)

    var title: String {
        switch self {
        case .daily(let kind): kind.boardTitle
        case .workout(let day): day.label
        }
    }
}

extension ReminderKind {
    /// The board's short row titles.
    var boardTitle: String {
        switch self {
        case .journal: "Journal"
        case .mind: "Mind check-in"
        case .dose: "Dose"
        case .gateFloor: "Readiness floor"
        }
    }

    var boardSymbol: String {
        switch self {
        case .journal: "book.closed"
        case .mind: "waveform.path"
        case .dose: "pills"
        case .gateFloor: "gauge.with.needle"
        }
    }
}

private struct DailyReminderRow: View {
    @Environment(\.jiTheme) private var theme
    let kind: ReminderKind
    let model: RemindersViewModel

    private var state: RemindersViewModel.DailyState? { model.daily[kind] }
    private var timeText: String {
        let t = state?.time ?? kind.defaultTime
        return ReminderScheduler.formatTime(hour: t.hour, minute: t.minute)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { state?.enabled ?? false },
            set: { next in Task { await model.setEnabled(kind, next) } }
        )) {
            JIRow(title: kind.boardTitle, subtitle: "Daily · \(timeText)", systemImage: kind.boardSymbol)
        }
        .tint(theme.color(.info))
        .disabled(state?.busy ?? false)
        .accessibilityLabel(kind.sectionTitle)
        .accessibilityValue("\(state?.enabled == true ? "On" : "Off"), daily at \(timeText). \(model.statusLine(for: kind))")
        .accessibilityIdentifier("reminders.\(kind.rawValue).toggle")
    }
}

/// The EDIT TIME card: pick a reminder, then its steppers (hour + minute for a daily one, ±15 min
/// for a workout day).
private struct EditTimeSection: View {
    @Environment(\.jiTheme) private var theme
    let model: RemindersViewModel
    @Binding var editing: ReminderEditTarget

    var body: some View {
        Section {
            Picker(selection: $editing) {
                ForEach(ReminderKind.allCases, id: \.self) { Text($0.boardTitle).tag(ReminderEditTarget.daily($0)) }
                ForEach(Weekday.displayOrder, id: \.self) { Text($0.label).tag(ReminderEditTarget.workout($0)) }
            } label: {
                Text("Time for").jiFont(.subheadline)
            }
            .accessibilityIdentifier("reminders.edit.target")

            switch editing {
            case .daily(let kind):
                let state = model.daily[kind]
                StepperRow(label: "Hour", value: String(format: "%02d", state?.time.hour ?? 0),
                           identifier: "reminders.\(kind.rawValue).hour",
                           onDecrease: { Task { await model.stepHour(kind, -1) } },
                           onIncrease: { Task { await model.stepHour(kind, 1) } })
                StepperRow(label: "Minute", value: String(format: "%02d", state?.time.minute ?? 0),
                           identifier: "reminders.\(kind.rawValue).minute",
                           onDecrease: { Task { await model.stepMinute(kind, -1) } },
                           onIncrease: { Task { await model.stepMinute(kind, 1) } })
            case .workout(let wd):
                StepperRow(label: "Time", value: model.workoutTimeLabel(wd),
                           identifier: "reminders.workout.\(wd.rawValue).time",
                           onDecrease: { Task { await model.shiftWorkoutTime(wd, minutes: -RemindersViewModel.workoutStepMinutes) } },
                           onIncrease: { Task { await model.shiftWorkoutTime(wd, minutes: RemindersViewModel.workoutStepMinutes) } })
                    .disabled(model.workouts[wd]?.busy ?? false)
            }
        } header: {
            Text("Edit time")
        } footer: {
            switch editing {
            case .daily(let kind):
                Text(model.statusLine(for: kind)).accessibilityIdentifier("reminders.\(kind.rawValue).status")
            case .workout:
                Text("Workout times move in 15-minute steps.")
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
            ForEach(Weekday.displayOrder, id: \.self) { wd in
                let s = model.workouts[wd]
                Toggle(isOn: Binding(
                    get: { s?.enabled ?? false },
                    set: { next in Task { await model.setWorkoutEnabled(wd, next) } }
                )) {
                    JIRow(title: wd.shortLabel) {
                        Text(model.workoutTimeLabel(wd)).jiFont(.subheadline, tint: .muted).monospacedDigit()
                    }
                }
                .tint(theme.color(.info))
                .disabled(s?.busy ?? false)
                .accessibilityLabel("\(wd.label) workout reminder")
                .accessibilityValue("\(s?.enabled == true ? "On" : "Off"), \(model.workoutTimeLabel(wd))")
                .accessibilityIdentifier("reminders.workout.\(wd.rawValue).toggle")
            }
        } header: {
            Text("Workout days")
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
