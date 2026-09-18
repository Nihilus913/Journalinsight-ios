import SwiftUI
import JIDesign

/// Behavior-tracking prompt card (oracle: `BehaviorCardDeck.tsx`). RN's version is a full
/// swipeable deck backed by its own `behaviorDeck`/`behaviorLogStore` modules, which are outside
/// this wave's owned Journal files/schema (not in `v3_capture`) — scoped down here to a static
/// placeholder card so the Journal screen has the same visual slot without inventing a new,
/// unreviewed persistence surface. A full port is a BACKLOG candidate (see W4 close-out).
public struct BehaviorCardDeck: View {
    public init() {}
    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 4) {
                Text("Behavior check-in").font(.system(size: 12, weight: .semibold)).foregroundStyle(JIColor.muted)
                Text("Coming soon").font(.system(size: 13)).foregroundStyle(JIColor.mutedNested)
                    // Identifier mirrors the oracle's `testID="behavior-card-deck"`.
                    .accessibilityIdentifier("behavior-card-deck")
            }
        }
    }
}
