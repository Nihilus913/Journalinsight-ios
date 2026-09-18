import SwiftUI
import JIDesign

/// Current/best/this-week streak stats (oracle: `StreakHeader.tsx`), fed by `JournalStreak`.
public struct StreakHeader: View {
    let stats: JournalStreak.Stats
    public init(stats: JournalStreak.Stats) { self.stats = stats }

    public var body: some View {
        Surface {
            HStack {
                stat("Current", "\(stats.current)")
                Spacer()
                stat("Best", "\(stats.best)")
                Spacer()
                stat("This week", "\(stats.thisWeek)")
                if let next = stats.nextMilestone {
                    Spacer()
                    stat("Next", "\(next)")
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).jiFont(.statValue, weight: .semibold).foregroundStyle(JIColor.text)
                .accessibilityLabel(label)
                .accessibilityValue(value)
            Text(label).jiFont(.caption).foregroundStyle(JIColor.muted)
        }
    }
}
