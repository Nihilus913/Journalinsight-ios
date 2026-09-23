import SwiftUI
import JICore
import JIDesign

/// B-57 §9 Coach: the one change for today as a bottom overlay card over the Day view (like
/// Bevel), not a step behind a button. ✕ or a swipe down dismisses it — in the morning flow that
/// is `coachAcknowledged`; re-opened from the summary line it is read-only (dismiss just closes).
/// Rule-based text, deliberately not styled as AI until B-51 writes it.
public struct CoachOverlayCard: View {
    let change: String
    let onDismiss: () -> Void
    @State private var drag: CGFloat = 0
    @Environment(\.jiTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A downward drag past this many points dismisses; anything shorter springs back.
    nonisolated static let dismissDistance: CGFloat = 60

    public init(change: String, onDismiss: @escaping () -> Void) {
        self.change = change; self.onDismiss = onDismiss
    }

    public var body: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("One change today").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .jiFont(.footnote, weight: .semibold)
                            .foregroundStyle(theme.color(.muted))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("today.coach.dismiss")
                }
                Text(change).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.coach.change")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous).stroke(theme.color(.hairlineOuter)))
        .shadow(color: theme.color(.text).opacity(0.14), radius: 16, y: 6)
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > Self.dismissDistance {
                        onDismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : JIMotion.standard) { drag = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Dismiss", onDismiss)
        .accessibilityIdentifier("today.coach.overlay")
    }
}
