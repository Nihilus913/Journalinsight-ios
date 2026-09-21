import SwiftUI

// MARK: B-33 §8.1 — size-class layout rules. Screens compose these; they never read sizes.

/// How many `.adaptive(minimum:)` tiles fit `availableWidth` (n tiles + n−1 gaps), floored at 1.
public nonisolated func columnCount(availableWidth: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
    guard minimum > 0 else { return 1 }
    return Swift.max(1, Int(((availableWidth + spacing) / (minimum + spacing)).rounded(.down)))
}

/// Every tile grid: 2-up on an iPhone, 3–4 in a readable column on iPad / Max landscape.
public struct Columns<Content: View>: View {
    let minimum: CGFloat, spacing: CGFloat, content: Content
    /// The tile floor grows with the type size, so AX3 drops a 2-up grid to 1-up instead of
    /// squeezing a card until its title breaks mid-word (§8.1 "reflows, never clips").
    @ScaledMetric(relativeTo: .body) private var scaledMinimum: CGFloat = 160

    public init(minimum: CGFloat = 160, spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.minimum = minimum; self.spacing = spacing; self.content = content()
        self._scaledMinimum = ScaledMetric(wrappedValue: minimum, relativeTo: .body)
    }
    public var body: some View {
        // `.top`: tiles in one row differ in height, and the default centre alignment offsets
        // the shorter card against its neighbour.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: scaledMinimum), spacing: spacing, alignment: .top)], spacing: spacing) { content }
    }
}

public extension View {
    /// Long lists and charts on a wide screen are capped and centred (720 pt) so lines stay readable.
    func readableColumn(maxWidth: CGFloat = 720) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

/// The only width fact a layout may depend on.
public nonisolated enum JIWidthClass: Sendable, Equatable { case compact, regular }

public nonisolated func adaptiveAxis(_ width: JIWidthClass) -> Axis { width == .regular ? .horizontal : .vertical }

/// Regular width composes side by side, compact stacks — hero + drivers, chart + legend,
/// strip + session, calendar + entries. No screen owns a second layout tree.
public struct AdaptiveHStack<Content: View>: View {
    let spacing: CGFloat, content: Content
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var widthClass: JIWidthClass { sizeClass == .regular ? .regular : .compact }
    #elseif os(macOS)
    private var widthClass: JIWidthClass { .regular }
    #else
    private var widthClass: JIWidthClass { .compact }
    #endif

    public init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing; self.content = content()
    }

    public var body: some View {
        let layout = adaptiveAxis(widthClass) == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout { content }
    }
}
