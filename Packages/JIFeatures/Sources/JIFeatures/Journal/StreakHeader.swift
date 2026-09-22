import SwiftUI
import JIDesign

/// Current/best/this-week streak stats (oracle: `StreakHeader.tsx`), fed by `JournalStreak`.
public struct StreakHeader: View {
    @Environment(\.jiTheme) private var theme
    let stats: JournalStreak.Stats
    public init(stats: JournalStreak.Stats) { self.stats = stats }

    /// B-46 item 9: no `Surface` of its own — this renders as a row inside a `List` section,
    /// whose inset-grouped background IS the card. (The Gallery/native previews put it in a
    /// `Surface` themselves, so nothing loses its card.)
    public var body: some View {
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
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).jiFont(.statValue, weight: .semibold).foregroundStyle(theme.color(.text))
                .accessibilityLabel(label)
                .accessibilityValue(value)
            Text(label).jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
    }
}
