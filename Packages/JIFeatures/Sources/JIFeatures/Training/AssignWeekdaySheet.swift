import SwiftUI
import JICore
import JIDesign

/// B-45 (c) / W-B46 L1: "Assign to weekday" — one plan session, one weekday (Mon = 0 … Sun = 6),
/// written through `PUT /api/v1/planning/plan-sessions/{id}`. The `Form` + `Section` + picker
/// shape is `EditTodayView`'s, so it reads like every other edit sheet in the app.
///
/// The sheet is deliberately honest about the two states the hub can put it in: a write in flight
/// shows a spinner on the Save button, and a write the hub *refused* (including an old hub that
/// has no such route — `PlanSessionUpdateUnavailable`) leaves the sheet open with a failure line
/// instead of dismissing as though it had worked.
///
/// B-52: an *unreachable* hub is no longer one of those states. The weekday is queued in the
/// `Outbox` before the hub is asked, so the sheet dismisses and the week strip carries a pending
/// marker until the drainer lands the row — the tap is never lost and never faked.
public struct AssignWeekdaySheet: View {
    public struct Session: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let weekday: Int?
        public init(id: Int, name: String, weekday: Int?) { self.id = id; self.name = name; self.weekday = weekday }
    }

    /// -1 is the picker's "not assigned" tag: `Picker` needs a non-optional `Hashable` selection,
    /// and a sentinel outside 0…6 keeps the mapping to `Int?` total in one place (`chosenWeekday`).
    static let unassignedTag = -1

    private let session: Session
    private let isSaving: Bool
    private let didFail: Bool
    private let onSave: (Int?) -> Void
    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.jiTheme) private var theme

    public init(session: Session, isSaving: Bool, didFail: Bool, onSave: @escaping (Int?) -> Void) {
        self.session = session; self.isSaving = isSaving; self.didFail = didFail; self.onSave = onSave
        _selection = State(initialValue: session.weekday ?? Self.unassignedTag)
    }

    private var chosenWeekday: Int? { selection == Self.unassignedTag ? nil : selection }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Weekday", selection: $selection) {
                        Text("Not assigned").tag(Self.unassignedTag)
                        ForEach(Array(planWeekdayNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("training-assign-weekday-picker")
                } header: {
                    Text("Which day is \(session.name)?")
                } footer: {
                    Text("The plan session shows on this weekday everywhere. Saved offline too — it syncs to the hub when it's reachable.")
                }

                if didFail {
                    Section {
                        Text("The hub refused this weekday — it may not support plan-session assignment yet. Nothing was saved.")
                            .foregroundStyle(theme.color(.danger))
                            .accessibilityIdentifier("training-assign-weekday-error")
                    }
                }
            }
            .navigationTitle("Assign to weekday")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onSave(chosenWeekday) } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("training-assign-weekday-save")
                }
            }
        }
        .jiTheme(.native)
    }
}
