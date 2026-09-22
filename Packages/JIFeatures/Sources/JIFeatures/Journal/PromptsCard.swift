import SwiftUI
import JIDesign

/// Today's 3 deterministic prompts (oracle: `PromptsCard.tsx`), fed by `JournalPrompts`.
public struct PromptsCard: View {
    @Environment(\.jiTheme) private var theme
    let prompts: [String]
    public init(prompts: [String] = JournalPrompts.todaysPrompts(Date())) { self.prompts = prompts }

    /// B-46 item 9: the title moved up into the `List` section header and the card chrome is the
    /// section's, so a prompt is a plain row with a bullet glyph instead of a line of body text
    /// inside a nested rounded rectangle.
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(prompts, id: \.self) { prompt in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "quote.opening").font(.caption2).foregroundStyle(theme.color(.mutedNested))
                    Text(prompt).jiFont(.footnote).foregroundStyle(theme.color(.text))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(prompt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
