import SwiftUI

/// W-GUI F5 — report §4.5 / §7 rule 2: the 44 × 44 glass round button. Back, edit, calendar,
/// plus — a chevron or a glyph, never a text link. Together with the coach overlay it is the
/// ONLY custom glass in the content layer (report §4.1); wrap the few on one screen in a single
/// `GlassEffectContainer`. `PressableScaleStyle` keeps the 0.92 / 100 ms press-in; the glass is
/// `.interactive()` so it also lights up under the finger. Reduce Transparency → the control
/// fill (the system drops the glass; the rim keeps the shape legible).
public nonisolated enum JIGlassButtonMetrics {
    public static let side: CGFloat = JITileHeight.glassButton.base
    /// The symbols a glass round button may carry (report §4.5: chevron only + the three
    /// navigation glyphs). Anything else is a card action and belongs in a row.
    public static let allowedSymbols: Set<String> = [
        "chevron.left", "chevron.right", "chevron.down", "chevron.up", "pencil", "calendar", "plus", "xmark", "ellipsis",
    ]
    public static func isAllowed(_ systemImage: String) -> Bool { allowedSymbols.contains(systemImage) }
}

public struct JIGlassButton: View {
    private let systemImage: String, label: String, action: () -> Void
    @Environment(\.jiTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.jiReduceTransparencyOverride) private var rtOverride
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = JIGlassButtonMetrics.side

    /// `label` is the VoiceOver name ("Back", "Edit", "Calendar", "Add") — required, never empty.
    public init(_ systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.label = label; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.color(.text))
                .frame(width: side, height: side)
                .contentShape(Circle())
                .modifier(GlassOrControl(opaque: rtOverride ?? reduceTransparency, fill: theme.color(.control), rim: theme.color(.hairlineOuter)))
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(label)
    }
}

/// The glass (or, under Reduce Transparency, the opaque control fill + hairline) behind a round button.
private struct GlassOrControl: ViewModifier {
    let opaque: Bool, fill: Color, rim: Color
    func body(content: Content) -> some View {
        if opaque {
            content.background(fill, in: Circle()).overlay(Circle().strokeBorder(rim, lineWidth: 1))
        } else {
            content.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

public extension View {
    /// W-GUI F5 — every pushed screen: hide the text back button, put a glass chevron in its
    /// place (report §7 rule 2: no text links, no text back). Wrap the screen's glass views in
    /// one `GlassEffectContainer` when there are several.
    func jiGlassBackButton() -> some View { modifier(JIGlassBackButtonModifier()) }
}

struct JIGlassBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .navigation) { JIGlassButton("chevron.left", label: "Back") { dismiss() } }
                #else
                ToolbarItem(placement: .topBarLeading) { JIGlassButton("chevron.left", label: "Back") { dismiss() } }
                #endif
            }
    }
}
