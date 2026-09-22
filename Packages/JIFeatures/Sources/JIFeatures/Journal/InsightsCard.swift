import SwiftUI
import JIDesign
import JIPersistence

/// Entry-count/avg-duration/preferred-time-of-day/longest-session summary (oracle:
/// `InsightsCard.tsx`), fed by `JournalInsights`. Never renders a zero silently for "no data" —
/// CLAUDE.md rule 5 — the empty state shows "—" the same way `avgDurationMin` already does.
public struct InsightsCard: View {
    @Environment(\.jiTheme) private var theme
    let entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                Text("Insights").jiFont(.label, weight: .semibold).foregroundStyle(theme.color(.muted))
                if entries.isEmpty {
                    Text("No entries yet").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                } else {
                    HStack {
                        stat("Entries", "\(JournalInsights.entryCount(entries))")
                        Spacer()
                        stat("Avg", "\(JournalInsights.avgDurationMin(entries)) min")
                        Spacer()
                        stat("Longest", "\(JournalInsights.longestSessionSec(entries) / 60) min")
                    }
                    if let preferred = JournalInsights.preferredTimeOfDay(entries) {
                        Text("Usually written: \(preferred.rawValue)").jiFont(.label).foregroundStyle(theme.color(.mutedNested))
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                .accessibilityLabel(label)
                .accessibilityValue(value)
            Text(label).jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
    }
}
