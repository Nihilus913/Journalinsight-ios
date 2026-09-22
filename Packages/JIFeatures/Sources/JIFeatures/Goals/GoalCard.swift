import SwiftUI
import JIPersistence
import JIDesign

/// W4-L3, mirrors `mobile/src/components/goals/GoalCard.tsx`: status-colored card (E13-4) with
/// +/- progress steppers and delete. `today` is injected (not `Date()`) so previews/tests are
/// deterministic — mirrors the oracle's own `todayISODate()` call site, just passed in here.
public struct GoalCard: View {
    @Environment(\.jiTheme) private var theme
    let goal: Goal
    let today: String
    let onStep: (Double) -> Void
    let onDelete: () -> Void

    public init(goal: Goal, today: String, onStep: @escaping (Double) -> Void, onDelete: @escaping () -> Void) {
        self.goal = goal; self.today = today; self.onStep = onStep; self.onDelete = onDelete
    }

    private static let step = 0.1

    private var status: GoalStatus { goalStatus(targetDate: goal.targetDate, progress: goal.progress, today: today) }

    private var badge: (String, Color)? {
        switch status {
        case .overdue: ("Overdue", theme.color(.danger))
        case .complete: ("Complete", theme.color(.go))
        case .onTrack: nil
        }
    }

    /// §2b.2: one inset-grouped row — the status colour moved from a drawn border to the native
    /// `ProgressView` tint + a tinted badge, delete is a swipe action, and the two ±10 % taps are
    /// a system `Stepper` (they were an unlabelled +/- pair).
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(goal.title).jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                Spacer(minLength: 8)
                if let badge {
                    Text(badge.0).jiFont(.micro, weight: .bold).foregroundStyle(badge.1)
                        .accessibilityLabel("\(goal.title) status: \(badge.0)")
                        .accessibilityIdentifier("goal-card-status")
                }
            }
            if let targetDate = goal.targetDate {
                Text("Target \(targetDate)").jiFont(.caption).foregroundStyle(theme.color(.muted))
            }

            // §8.1: no fixed geometry — the system bar takes the row's width, whatever it is.
            ProgressView(value: clampProgress(goal.progress))
                .tint(status == .overdue ? theme.color(.danger) : theme.color(.go))
                .accessibilityLabel("Progress")
                .accessibilityValue(formatPercent(goal.progress))

            Stepper(formatPercent(goal.progress)) {
                onStep(Self.step)
            } onDecrement: {
                onStep(-Self.step)
            }
            .accessibilityLabel("\(goal.title) progress")
            .accessibilityValue(formatPercent(goal.progress))
            .accessibilityIdentifier("goal-card-progress-stepper")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityLabel("Delete \(goal.title)")
                .accessibilityIdentifier("goal-card-delete")
        }
    }
}

/// Port of `mobile/src/goals/progress.ts::formatPercent`: clamp first, then round to whole percent.
public func formatPercent(_ value: Double) -> String { "\(Int((clampProgress(value) * 100).rounded()))%" }
