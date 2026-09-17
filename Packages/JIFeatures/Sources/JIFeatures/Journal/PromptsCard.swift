import SwiftUI
import JIDesign

/// Today's 3 deterministic prompts (oracle: `PromptsCard.tsx`), fed by `JournalPrompts`.
public struct PromptsCard: View {
    let prompts: [String]
    public init(prompts: [String] = JournalPrompts.todaysPrompts(Date())) { self.prompts = prompts }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's prompts").font(.system(size: 12, weight: .semibold)).foregroundStyle(JIColor.muted)
                ForEach(prompts, id: \.self) { prompt in
                    Text("· \(prompt)").font(.system(size: 13)).foregroundStyle(JIColor.text)
                }
            }
        }
    }
}
