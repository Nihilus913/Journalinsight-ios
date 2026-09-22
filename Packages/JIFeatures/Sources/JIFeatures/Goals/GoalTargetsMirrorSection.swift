import SwiftUI
import JICore
import JIDesign

/// W4-L3 — a small read-only recap of the structured document that was just loaded/saved (the
/// `goal_targets_mirror` local-first copy `GoalsSetupViewModel.save` keeps in sync). Rule 5: every
/// value that could be missing renders "—", never 0.
public struct GoalTargetsMirrorSection: View {
    @Environment(\.jiTheme) private var theme
    let goals: Goals

    public init(goals: Goals) { self.goals = goals }

    /// §2b.2: a real `List` section of 44-pt rows — callers place it straight into a `List`.
    public var body: some View {
        Section {
            row("Weight", String(format: "%.1f kg", goals.weight.targetKg))
            row("Bench", goals.strength.first { $0.exercise == "bench" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
            row("Row", goals.strength.first { $0.exercise == "row" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
            row("Steps/day", goals.stepsDaily.map(String.init) ?? "—")
            row("Kcal", goals.nutrition.kcalGoal.map { "\(Int($0))" } ?? "—")
        } header: {
            Text("Current targets").accessibilityIdentifier("goal-targets-mirror-heading")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        JIRow(title: label) { Text(value).jiFont(.footnote, weight: .semibold) }
            .accessibilityLabel("\(label), \(value)")
            .accessibilityIdentifier("goal-target-\(label)")
    }
}
