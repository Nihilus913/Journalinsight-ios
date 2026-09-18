import SwiftUI
import JIPersistence
import JIDesign

/// W4-L3, mirrors `mobile/src/components/goals/GoalCard.tsx`: status-colored card (E13-4) with
/// +/- progress steppers and delete. `today` is injected (not `Date()`) so previews/tests are
/// deterministic — mirrors the oracle's own `todayISODate()` call site, just passed in here.
public struct GoalCard: View {
    let goal: Goal
    let today: String
    let onStep: (Double) -> Void
    let onDelete: () -> Void

    public init(goal: Goal, today: String, onStep: @escaping (Double) -> Void, onDelete: @escaping () -> Void) {
        self.goal = goal; self.today = today; self.onStep = onStep; self.onDelete = onDelete
    }

    private static let step = 0.1

    private var status: GoalStatus { goalStatus(targetDate: goal.targetDate, progress: goal.progress, today: today) }

    private var borderColor: Color {
        switch status {
        case .overdue: JIColor.danger
        case .complete: JIColor.go
        case .onTrack: JIColor.nested
        }
    }

    private var badge: (String, Color)? {
        switch status {
        case .overdue: ("Overdue", JIColor.danger)
        case .complete: ("Complete", JIColor.go)
        case .onTrack: nil
        }
    }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title).font(.subheadline.bold()).foregroundStyle(JIColor.text)
                        HStack(spacing: 6) {
                            if let targetDate = goal.targetDate {
                                Text("Target \(targetDate)").font(.caption).foregroundStyle(JIColor.muted)
                            }
                            if let badge {
                                Text(badge.0).font(.caption2.bold()).foregroundStyle(badge.1)
                                    .accessibilityLabel("\(goal.title) status: \(badge.0)")
                                    .accessibilityIdentifier("goal-card-status")
                            }
                        }
                    }
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "xmark").foregroundStyle(JIColor.danger)
                    }
                    .accessibilityLabel("Delete \(goal.title)")
                    .accessibilityIdentifier("goal-card-delete")
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(JIColor.muted.opacity(0.3))
                        Capsule()
                            .fill(status == .overdue ? JIColor.danger : JIColor.go)
                            .frame(width: geo.size.width * clampProgress(goal.progress))
                    }
                }
                .frame(height: 4)
                .accessibilityLabel("Progress")
                .accessibilityValue(formatPercent(goal.progress))

                HStack {
                    Text(formatPercent(goal.progress)).font(.caption.bold()).foregroundStyle(JIColor.text)
                    Spacer()
                    Button { onStep(-Self.step) } label: { Image(systemName: "minus") }
                        .accessibilityLabel("Decrease progress")
                        .accessibilityIdentifier("goal-card-decrease")
                    Button { onStep(Self.step) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Increase progress")
                        .accessibilityIdentifier("goal-card-increase")
                }
            }
        }
    }
}

/// Port of `mobile/src/goals/progress.ts::formatPercent`: clamp first, then round to whole percent.
public func formatPercent(_ value: Double) -> String { "\(Int((clampProgress(value) * 100).rounded()))%" }
