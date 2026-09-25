import JICore
import JIDesign
import JISnapshot
import SwiftUI

/// B-57 W2 (B-73) board 6/07 KpiWidgetMedium: "Left to your goals", four columns with a progress
/// bar each. The goals are the user's own; an unset goal's column shows "—" over "Set your goal".
struct MacrosLeftFace: View {
    let macros: SnapshotMacros
    private let theme = widgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Left to your goals").jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.muted))
            HStack(alignment: .top, spacing: 10) {
                column("kcal", macros.kcal, unit: "", role: .kcal)
                column("Protein", macros.protein, unit: " g", role: .protein)
                column("Carbs", macros.carbs, unit: " g", role: .carbs)
                column("Fat", macros.fat, unit: " g", role: .fat)
            }
            Spacer(minLength: 0)
            HStack {
                // The only fuel line allowed (never pre-workout advice).
                Text("Carbs go in the meal after the session").jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(1)
                Spacer(minLength: 4)
                if let asOf = macros.asOf {
                    Text("Health \(asOf.formatted(date: .omitted, time: .shortened))").jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func column(_ label: String, _ m: SnapshotMacro?, unit: String, role: JIColorRole) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(role))
            Text(verbatim: m.map { "\(Int($0.left.rounded()))\(unit)" } ?? "—")
                .jiNumeral(.numeralSmall).foregroundStyle(theme.color(m == nil ? .muted : .text)).lineLimit(1).minimumScaleFactor(0.5)
            Text(verbatim: m.map { "left of \(Int($0.goal.rounded()))\(unit)" } ?? MacroGoals.setGoalCopy)
                .jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value: m.map { min(1, max(0, 1 - $0.left / max($0.goal, 1))) } ?? 0).tint(theme.color(role))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
