import SwiftUI
import JIDesign

/// Persistent, non-negotiable rail (mental-health spec, oracle `Disclaimer.tsx`): tracking-not-
/// diagnosis framing + the CH crisis line, shown on every render of the Journal tab.
public struct Disclaimer: View {
    public init() {}
    public var body: some View {
        Text("Tracking, not diagnosis · In crisis? 143 — Die Dargebotene Hand")
            .font(.system(size: 11))
            .foregroundStyle(JIColor.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Tracking, not diagnosis. In crisis? Call 143, Die Dargebotene Hand.")
    }
}
