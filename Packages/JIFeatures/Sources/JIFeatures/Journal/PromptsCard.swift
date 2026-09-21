import SwiftUI
import JIDesign

/// Today's 3 deterministic prompts (oracle: `PromptsCard.tsx`), fed by `JournalPrompts`.
public struct PromptsCard: View {
    @Environment(\.jiTheme) private var theme
    let prompts: [String]
    public init(prompts: [String] = JournalPrompts.todaysPrompts(Date())) { self.prompts = prompts }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's prompts").jiFont(.label, weight: .semibold).foregroundStyle(theme.color(.muted))
                ForEach(prompts, id: \.self) { prompt in
                    Text("· \(prompt)").jiFont(.footnote).foregroundStyle(theme.color(.text))
                        .accessibilityLabel(prompt)
                }
            }
        }
    }
}
