import SwiftUI
import JICore
import JIDesign

// MARK: - W-OFFLINE2 OFF2-4 (B-50 slice 2): completed workouts with no hub

/// "Tue 6 Oct" for a history row's start, in the device's calendar; nil when the row has no start.
public nonisolated func trainingHistoryDateLabel(_ activity: DayActivity, calendar: Calendar = .current) -> String? {
    guard let start = activity.startDate else { return nil }
    let f = DateFormatter()
    f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f.string(from: start)
}

/// The no-hub Training history: the last two weeks of Apple Health workouts, read on the device.
/// A row opens the HR-only Activity detail when `isTappable` says a series can exist.
struct TrainingHistoryList: View {
    let workouts: [DayActivity]
    let loaded: Bool
    let isTappable: (DayActivity) -> Bool
    let open: (DayActivity) -> Void
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JISectionHeader("Workouts · Apple Health")
            Surface(level: 1, padding: JISpacing.cardPadding) { content }
                .accessibilityIdentifier("training-history")
            Text("Your plan and progression need the hub; these are the workouts on this iPhone.")
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
        }
    }

    @ViewBuilder private var content: some View {
        if workouts.isEmpty {
            Text(emptyText).jiFont(.body).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("training-history-empty")
        } else {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                ForEach(workouts.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    row(workouts[index]).accessibilityIdentifier("training-history-row-\(index)")
                }
            }
        }
    }

    private var emptyText: String {
        loaded ? "No workouts in Apple Health in the last \(TrainingViewModel.historyDays) days." : "Reading Apple Health…"
    }

    private func opener(_ activity: DayActivity) -> (@MainActor (DayActivity) -> Void)? {
        guard isTappable(activity) else { return nil }
        let open = self.open
        return { open($0) }
    }

    private func row(_ activity: DayActivity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let date = trainingHistoryDateLabel(activity) {
                Text(date).jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
            CompletedWorkoutRow(activity: activity).environment(\.openActivityDetail, opener(activity))
        }
    }
}
