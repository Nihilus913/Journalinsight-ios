import SwiftUI
import JICore
import JIDesign

/// W4-L3 — a small read-only recap of the structured document that was just loaded/saved (the
/// `goal_targets_mirror` local-first copy `GoalsSetupViewModel.save` keeps in sync). Rule 5: every
/// value that could be missing renders "—", never 0.
public struct GoalTargetsMirrorSection: View {
    let goals: Goals

    public init(goals: Goals) { self.goals = goals }

    public var body: some View {
        Surface(level: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current targets").font(.caption.bold()).foregroundStyle(JIColor.muted).textCase(.uppercase)
                    .accessibilityIdentifier("goal-targets-mirror-heading")
                row("Weight", String(format: "%.1f kg", goals.weight.targetKg))
                row("Bench", goals.strength.first { $0.exercise == "bench" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
                row("Row", goals.strength.first { $0.exercise == "row" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
                row("Steps/day", goals.stepsDaily.map(String.init) ?? "—")
                row("Kcal", goals.nutrition.kcalGoal.map { "\(Int($0))" } ?? "—")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(JIColor.text)
            Spacer()
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(JIColor.text)
                .accessibilityLabel("\(label), \(value)")
                .accessibilityIdentifier("goal-target-\(label)")
        }
    }
}
