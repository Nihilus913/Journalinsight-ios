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
    @State private var armedDecrease: Set<String> = [] // "weight" or "reps:<exerciseId>"

    public init(exercises: [Exercise], pendingIds: Set<Int> = [], failedIds: Set<Int> = [], onUpdate: @escaping (Exercise, ExerciseUpdate) -> Void) {
        self.exercises = exercises; self.pendingIds = pendingIds; self.failedIds = failedIds; self.onUpdate = onUpdate
    }

    public var body: some View {
        let lift = liftDefs.first { $0.key == selected } ?? liftDefs[0]
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Strength progression").font(.caption.weight(.semibold)).foregroundStyle(JIColor.muted)
                Text("Double progression").font(.caption2).foregroundStyle(JIColor.muted)
                HStack(spacing: 6) {
                    ForEach(liftDefs) { l in
                        Button(l.label) { selected = l.key }
                            .buttonStyle(.pressableScale)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(l.key == selected ? JIColor.info : JIColor.surface2, in: Capsule())
                            .foregroundStyle(l.key == selected ? JIColor.bg : JIColor.muted)
                            .accessibilityLabel("\(l.label) tab")
                    }
                }
                liftPanel(lift)
            }
        }
    }

    @ViewBuilder
    private func liftPanel(_ lift: LiftDef) -> some View {
        let rows = exercises.filter { lift.match($0.exerciseName) }
        if rows.isEmpty {
            Text("Not currently tracked in the active plan.").font(.footnote).foregroundStyle(JIColor.muted)
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
                Text(canonical.exerciseName).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                HStack {
                    Text(weight != nil ? "\(weight!.formatted()) kg" : "—")
                        .font(.title2.bold()).foregroundStyle(JIColor.text)
                    Spacer()
                    if canStepWeight {
                        stepButton(symbol: "−", requireConfirm: true, armKey: "weight:\(canonical.exerciseId)", disabled: pending) {
                            for row in rows { onUpdate(row, ExerciseUpdate(currentWeightKg: max(0, weight! - step!), progressionStepKg: step!, sets: row.sets, repsTarget: parseRepsTarget(row.repsTarget))) }
                        }
                        stepButton(symbol: "+", requireConfirm: false, armKey: "weight+:\(canonical.exerciseId)", disabled: pending) {
                            for row in rows { onUpdate(row, ExerciseUpdate(currentWeightKg: weight! + step!, progressionStepKg: step!, sets: row.sets, repsTarget: parseRepsTarget(row.repsTarget))) }
                        }
                    }
                }
                if failed { Text("Couldn't save — try again.").font(.caption).foregroundStyle(JIColor.danger) }
                ForEach(rows, id: \.exerciseId) { row in sessionRepsRow(row, showSession: rows.count > 1) }
            }
            .opacity(pending ? 0.6 : 1)
        }
    }

    private func sessionRepsRow(_ exercise: Exercise, showSession: Bool) -> some View {
        let reps = parseRepsTarget(exercise.repsTarget)
        return HStack {
            Text(exercise.sessionName).font(.caption2).foregroundStyle(JIColor.muted)
            Spacer()
            Text(formatSetsReps(sets: exercise.sets, reps: reps)).font(.caption).foregroundStyle(JIColor.muted)
            if let reps {
                stepButton(symbol: "−", requireConfirm: true, armKey: "reps:\(exercise.exerciseId)", disabled: pendingIds.contains(exercise.exerciseId)) {
                    onUpdate(exercise, ExerciseUpdate(currentWeightKg: exercise.currentWeightKg ?? 0, progressionStepKg: exercise.progressionStepKg ?? 0, sets: exercise.sets, repsTarget: max(1, reps - 1)))
                }
                stepButton(symbol: "+", requireConfirm: false, armKey: "reps+:\(exercise.exerciseId)", disabled: pendingIds.contains(exercise.exerciseId)) {
                    onUpdate(exercise, ExerciseUpdate(currentWeightKg: exercise.currentWeightKg ?? 0, progressionStepKg: exercise.progressionStepKg ?? 0, sets: exercise.sets, repsTarget: reps + 1))
                }
            }
        }
    }

    private func stepButton(symbol: String, requireConfirm: Bool, armKey: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        let armed = armedDecrease.contains(armKey)
        return Button {
            if requireConfirm && !armed { armedDecrease.insert(armKey); return }
            armedDecrease.remove(armKey)
            action()
        } label: {
            Text(symbol).font(.callout.bold())
                .frame(width: 30, height: 30)
                .background(armed ? JIColor.reduced.opacity(0.2) : JIColor.surface, in: Circle())
                .foregroundStyle(armed ? JIColor.reduced : JIColor.text)
        }
        .buttonStyle(.pressableScale)
        .disabled(disabled)
        .accessibilityLabel(armed ? "tap again to confirm" : symbol == "−" ? "decrease" : "increase")
    }
}

/// Port of `mobile/src/lib/liftFormat.ts`'s `formatSetsReps` — "3×10 reps" / "3 sets" / "10 reps" / "—".
nonisolated public func formatSetsReps(sets: Int?, reps: Int?) -> String {
    if let sets, let reps { return "\(sets)×\(reps) reps" }
    if let sets { return "\(sets) sets" }
    if let reps { return "\(reps) reps" }
    return "—"
}
