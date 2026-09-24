import SwiftUI
import JIDesign

#if canImport(WorkoutKit)
/// B-57 W1: the Training header's Watch line, from the Send-to-Watch state. `nil` (not wired)
/// makes no claim at all.
public nonisolated func trainingWatchLine(_ state: SendToWatchViewModel.State?) -> String? {
    guard let state else { return nil }
    switch state {
    case .sent: return "On your Watch"
    case .sending: return "Sending to your Watch…"
    case .idle, .loading, .authDenied, .error: return "Not on your Watch yet"
    }
}
#endif

/// B-57 W1 Training header: the session title at 32/800 (system `.largeTitle` heavy — no 32-pt
/// token exists and adding one would re-pin JITypography), the synced pill, the Watch state.
struct TrainingSessionHeader: View {
    let sessionName: String?, fetchedAt: Date?, watchLine: String?
    @Environment(\.jiTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Spacer(); SyncedPill(date: fetchedAt) }
            Text(sessionName ?? "— \(JIMissingReason.noData.rawValue)")
                .font(.largeTitle.weight(.heavy)).foregroundStyle(theme.color(sessionName == nil ? .muted : .text))
                .lineLimit(2).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("training-session-title")
            if let watchLine {
                Label(watchLine, systemImage: "applewatch").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("training-watch-state")
            }
        }
    }
}
