import SwiftUI
import JICore
import JIDesign

/// Fixed 4-lift set (oracle: `LiftSteppers.tsx`'s `LIFTS`), matched by name against the active
/// plan's exercises — a lift absent from the plan renders its panel's empty state.
private struct LiftDef: Identifiable { let key: String; let label: String; let match: (String) -> Bool
    var id: String { key }
}
private let liftDefs: [LiftDef] = [
    LiftDef(key: "bench", label: "Bench", match: { $0.localizedCaseInsensitiveContains("bench") }),
    LiftDef(key: "row", label: "Row", match: { $0.localizedCaseInsensitiveContains("row") }),
    LiftDef(key: "curls", label: "Curls", match: { $0.localizedCaseInsensitiveContains("curl") }),
    LiftDef(key: "dips", label: "Dips", match: { $0.localizedCaseInsensitiveContains("dip") }),
]

/// Double-progression steppers for the 4 tracked lifts (oracle: `LiftSteppers.tsx`). Weight is one
/// number per lift, written to every matching session row together; reps stay per-session.
/// `requireConfirm` on "-" (E18-7 asymmetric confirm) is simplified to a 2-tap arm here rather than
/// the oracle's timed re-arm window — same intent (a stray tap can't silently walk progress back
/// down), smaller surface for this wave.
public struct LiftSteppers: View {
    let exercises: [Exercise]
    let pendingIds: Set<Int>
    let failedIds: Set<Int>
    let onUpdate: (Exercise, ExerciseUpdate) -> Void
    @State private var selected = liftDefs[0].key
    @Environment(\.jiTheme) private var theme
    @State private var armedDecrease: Set<String> = [] // "weight" or "reps:<exerciseId>"

    public init(exercises: [Exercise], pendingIds: Set<Int> = [], failedIds: Set<Int> = [], onUpdate: @escaping (Exercise, ExerciseUpdate) -> Void) {
        self.exercises = exercises; self.pendingIds = pendingIds; self.failedIds = failedIds; self.onUpdate = onUpdate
    }

    public var body: some View {
        let lift = liftDefs.first { $0.key == selected } ?? liftDefs[0]
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Strength progression").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .accessibilityAddTraits(.isHeader)
                Text("Double progression").jiFont(.micro).foregroundStyle(theme.color(.muted))
                // §2b.3: the hand-rolled capsule tabs become the system segmented control — it
                // scrolls, wraps and reflows at AX sizes on its own, which the capsule row did not.
                Picker("Lift", selection: $selected) {
                    ForEach(liftDefs) { l in
                        Text(l.label).tag(l.key).accessibilityIdentifier("lift-tab-\(l.key)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lift-tabs")
                liftPanel(lift)
            }
        }
    }

    @ViewBuilder
    private func liftPanel(_ lift: LiftDef) -> some View {
        let rows = exercises.filter { lift.match($0.exerciseName) }
        if rows.isEmpty {
            Text("Not currently tracked in the active plan.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
        } else {
            liftCard(rows)
        }
    }

    private func liftCard(_ rows: [Exercise]) -> some View {
        let canonical = rows[0]
        let weight = canonical.currentWeightKg
        let step = canonical.progressionStepKg
        let canStepWeight = weight != nil && step != nil && step! > 0
        let pending = rows.contains { pendingIds.contains($0.exerciseId) }
        let failed = rows.contains { failedIds.contains($0.exerciseId) }
        return Surface(level: 2) {
            VStack(alignment: .leading, spacing: 8) {
                Text(canonical.exerciseName).jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Text(weight != nil ? "\(weight!.formatted()) kg" : "—")
                        .jiNumeral(.numeralCompact).foregroundStyle(theme.color(.text))
                        .accessibilityLabel("\(canonical.exerciseName) weight")
                        .accessibilityValue(weight != nil ? "\(weight!.formatted()) kg" : "no data")
                    Spacer()
                    if canStepWeight {
                        stepButton(symbol: "−", label: liftStepperLabel(exerciseName: canonical.exerciseName, sessionName: nil, quantity: .weight, direction: .decrease), requireConfirm: true, armKey: "weight:\(canonical.exerciseId)", disabled: pending) {
                            for row in rows { onUpdate(row, ExerciseUpdate(currentWeightKg: max(0, weight! - step!), progressionStepKg: step!, sets: row.sets, repsTarget: parseRepsTarget(row.repsTarget))) }
                        }
                        stepButton(symbol: "+", label: liftStepperLabel(exerciseName: canonical.exerciseName, sessionName: nil, quantity: .weight, direction: .increase), requireConfirm: false, armKey: "weight+:\(canonical.exerciseId)", disabled: pending) {
                            for row in rows { onUpdate(row, ExerciseUpdate(currentWeightKg: weight! + step!, progressionStepKg: step!, sets: row.sets, repsTarget: parseRepsTarget(row.repsTarget))) }
                        }
                    }
                }
                if failed { Text("Couldn't save — try again.").jiFont(.caption).foregroundStyle(theme.color(.danger)).accessibilityIdentifier("lift-save-failed") }
                ForEach(rows, id: \.exerciseId) { row in sessionRepsRow(row, showSession: rows.count > 1) }
            }
            .opacity(pending ? 0.6 : 1)
        }
    }

    private func sessionRepsRow(_ exercise: Exercise, showSession: Bool) -> some View {
        let reps = parseRepsTarget(exercise.repsTarget)
        return HStack {
            Text(exercise.sessionName).font(.caption2).foregroundStyle(theme.color(.muted))
            Spacer()
            Text(formatSetsReps(sets: exercise.sets, reps: reps)).font(.caption).foregroundStyle(theme.color(.muted))
                .accessibilityLabel("\(exercise.sessionName) \(exercise.exerciseName)")
                .accessibilityValue(formatSetsReps(sets: exercise.sets, reps: reps))
            if let reps {
                stepButton(symbol: "−", label: liftStepperLabel(exerciseName: exercise.exerciseName, sessionName: showSession ? exercise.sessionName : nil, quantity: .reps, direction: .decrease), requireConfirm: true, armKey: "reps:\(exercise.exerciseId)", disabled: pendingIds.contains(exercise.exerciseId)) {
                    onUpdate(exercise, ExerciseUpdate(currentWeightKg: exercise.currentWeightKg ?? 0, progressionStepKg: exercise.progressionStepKg ?? 0, sets: exercise.sets, repsTarget: max(1, reps - 1)))
                }
                stepButton(symbol: "+", label: liftStepperLabel(exerciseName: exercise.exerciseName, sessionName: showSession ? exercise.sessionName : nil, quantity: .reps, direction: .increase), requireConfirm: false, armKey: "reps+:\(exercise.exerciseId)", disabled: pendingIds.contains(exercise.exerciseId)) {
                    onUpdate(exercise, ExerciseUpdate(currentWeightKg: exercise.currentWeightKg ?? 0, progressionStepKg: exercise.progressionStepKg ?? 0, sets: exercise.sets, repsTarget: reps + 1))
                }
            }
        }
    }

    /// B-28 (W8-L3): `label` is RN's per-exercise a11y string from `liftStepperLabel` — the
    /// armed state appends " — tap again to confirm" exactly like `StepButton` in `LiftSteppers.tsx`.
    private func stepButton(symbol: String, label: String, requireConfirm: Bool, armKey: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        let armed = armedDecrease.contains(armKey)
        return Button {
            if requireConfirm && !armed { armedDecrease.insert(armKey); return }
            armedDecrease.remove(armKey)
            action()
        } label: {
            Text(symbol).font(.callout.bold())
                .frame(width: 30, height: 30)
                .background(armed ? theme.color(.reduced).opacity(0.2) : theme.color(.control), in: Circle())
                .foregroundStyle(armed ? theme.color(.reduced) : theme.color(.text))
        }
        .buttonStyle(.pressableScale)
        .disabled(disabled)
        .accessibilityLabel(liftStepperLabel(label, armed: armed))
        .accessibilityIdentifier("lift-step-\(armKey)")
    }
}

// MARK: - Per-exercise stepper a11y strings (port of `LiftSteppers.tsx` `StepButton` / `SessionRepsRow` / `LiftCard`)

/// Which number a stepper moves.
public nonisolated enum LiftStepperQuantity: String, Sendable { case weight, reps }
/// Which way it moves.
public nonisolated enum LiftStepperDirection: String, Sendable { case increase, decrease }

/// RN: `${labelPrefix}${exercise.exercise_name} reps increase` / `${canonical.exercise_name} weight decrease`.
/// `sessionName` is the `labelPrefix` — passed only for reps rows of a multi-session lift
/// (`showSessionInLabel = rows.length > 1`); weight steppers never carry it.
nonisolated public func liftStepperLabel(exerciseName: String, sessionName: String?, quantity: LiftStepperQuantity, direction: LiftStepperDirection) -> String {
    let prefix = sessionName.map { "\($0) " } ?? ""
    return "\(prefix)\(exerciseName) \(quantity.rawValue) \(direction.rawValue)"
}

/// RN: `armed ? `${accessibilityLabel} — tap again to confirm` : accessibilityLabel`.
nonisolated public func liftStepperLabel(_ label: String, armed: Bool) -> String {
    armed ? "\(label) — tap again to confirm" : label
}

/// Port of `mobile/src/lib/liftFormat.ts`'s `formatSetsReps` — "3×10 reps" / "3 sets" / "10 reps" / "—".
nonisolated public func formatSetsReps(sets: Int?, reps: Int?) -> String {
    if let sets, let reps { return "\(sets)×\(reps) reps" }
    if let sets { return "\(sets) sets" }
    if let reps { return "\(reps) reps" }
    return "—"
}
