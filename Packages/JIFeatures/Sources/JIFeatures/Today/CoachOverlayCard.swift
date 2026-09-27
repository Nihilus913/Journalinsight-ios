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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.jiReduceTransparencyOverride) private var rtOverride

    /// A downward drag past this many points dismisses; anything shorter springs back.
    nonisolated static let dismissDistance: CGFloat = 60

    /// W-FIX2 BUG-16: Today is drawn behind the chrome-only TabView, so the bottom overlay has to
    /// lift itself above the floating tab bar (on a phone) or its sentence sits under the bar.
    nonisolated static func bottomClearance(_ width: JIWidthClass) -> CGFloat { tabBarBottomClearance(width) }

    public init(change: String, onDismiss: @escaping () -> Void) {
        self.change = change; self.onDismiss = onDismiss
    }

    public var body: some View {
        // W-GUI F8 (report §4.1): the coach overlay is the navigation layer's ONE custom glass —
        // `.glassEffect` sampling the Day behind it; Reduce Transparency → the opaque card.
        GlassEffectContainer {
            CoachGlassSurface(opaque: rtOverride ?? reduceTransparency, radius: theme.radius(.card)) {
                cardContent
            }
        }
        .padding(.bottom, Self.bottomClearance(sizeClass == .regular ? .regular : .compact))
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

    private var cardContent: some View {
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
}

/// The overlay's material: Liquid Glass (regular) in a 26 pt rect, or — under Reduce
/// Transparency — the opaque level-1 `Surface`. Never both, never nested (report §4.1).
struct CoachGlassSurface<Content: View>: View {
    let opaque: Bool, radius: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        if opaque {
            Surface(level: 1, padding: 20) { content() }
        } else {
            content()
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
        }
    }
}
