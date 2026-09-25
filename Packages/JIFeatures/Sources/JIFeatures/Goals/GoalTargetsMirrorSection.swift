import SwiftUI
import JICore
import JIDesign

/// W4-L3 — a small read-only recap of the structured document that was just loaded/saved (the
/// `goal_targets_mirror` local-first copy `GoalsSetupViewModel.save` keeps in sync). Rule 5: every
/// value that could be missing renders "—", never 0.
/// B-73 (W-B57-W2 fixer GOALS-HUB-SEED): the Kcal row is the user's own target (`goals.macros`),
/// never the hub document's seeded `nutrition.kcal_goal` (TEMP bridge until B-50). Unset = "—".
public nonisolated func goalTargetsMirrorKcalText(macros: MacroGoals?) -> String {
    guard let k = macros?.targetKcal, k.isFinite, k > 0 else { return "—" }
    return String(Int(k.rounded()))
}

public struct GoalTargetsMirrorSection: View {
    @Environment(\.jiTheme) private var theme
    @Environment(\.nutritionGoals) private var nutritionGoals
    let goals: Goals
    /// The user's goals when the caller holds a fresher copy than the app-root injection (GoalsSetup
    /// right after a save); nil = read the injected `nutritionGoals`.
    let macros: MacroGoals?

    public init(goals: Goals, macros: MacroGoals? = nil) { self.goals = goals; self.macros = macros }

    /// §2b.2: a real `List` section of 44-pt rows — callers place it straight into a `List`.
    public var body: some View {
        Section {
            row("Weight", String(format: "%.1f kg", goals.weight.targetKg))
            row("Bench", goals.strength.first { $0.exercise == "bench" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
            row("Row", goals.strength.first { $0.exercise == "row" }.map { String(format: "%.1f kg", $0.targetKg) } ?? "—")
            row("Steps/day", goals.stepsDaily.map(String.init) ?? "—")
            row("Kcal", goalTargetsMirrorKcalText(macros: macros ?? nutritionGoals.macros))
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
