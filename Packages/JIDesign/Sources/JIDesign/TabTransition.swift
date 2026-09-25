import SwiftUI

/// Pure crossfade math for the tab-switch transition (fixes the W1 hard-cut —
/// see CONTEXT-IOS-FOUNDATION.md §Step 4: "tab switch EXPECTED to FAIL (hard cut
/// — W2 story)"). `progress` is `CrossfadeModifier.animatableData`; SwiftUI
/// interpolates it continuously across the transition, so this function is
/// evaluated at every intermediate frame rather than only at the two endpoints.
public nonisolated func tabCrossfadeOpacity(progress: Double, forIncoming: Bool) -> Double {
    let clamped = min(max(progress, 0), 1)
    return forIncoming ? clamped : 1 - clamped
}

/// Counts, out of an evenly spaced `samples`-point sweep of `progress` in
/// `[0, 1]`, how many land *strictly between* fully-hidden and fully-shown for
/// the incoming layer. A hard cut would only ever show 0 or 1; a real crossfade
/// produces several in-between values — this is the acceptance check for
/// "transition shows ≥3 intermediate frames".
public nonisolated func tabCrossfadeIntermediateFrameCount(samples: Int = 5) -> Int {
    guard samples > 1 else { return 0 }
    return (0..<samples)
        .map { Double($0) / Double(samples - 1) }
        .filter { tabCrossfadeOpacity(progress: $0, forIncoming: true).isStrictlyBetweenZeroAndOne }
        .count
}

private extension Double {
    nonisolated var isStrictlyBetweenZeroAndOne: Bool { self > 0 && self < 1 }
}

/// Animatable crossfade modifier: SwiftUI drives `progress` frame-by-frame
/// during the transition (not just at the start/end), so `body(content:)` — and
/// therefore `tabCrossfadeOpacity` — runs at every intermediate frame. This is
/// what turns an instant W1-style switch into a real animation.
private nonisolated struct CrossfadeModifier: ViewModifier, Animatable {
    var progress: Double
    let incoming: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(tabCrossfadeOpacity(progress: progress, forIncoming: incoming))
    }
}

public extension AnyTransition {
    /// Explicit cross-fade for a tab switch — replaces an instant `.id`-keyed
    /// swap with a `progress`-animated one so removal and insertion both play
    /// out over several frames instead of jump-cutting.
    static var jiTabCrossfade: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: CrossfadeModifier(progress: 0, incoming: true),
                identity: CrossfadeModifier(progress: 1, incoming: true)
            ),
            removal: .modifier(
                active: CrossfadeModifier(progress: 1, incoming: false),
                identity: CrossfadeModifier(progress: 0, incoming: false)
            )
        )
    }
}

/// Drop-in tab-switch container: crossfades its content whenever `selection`
/// changes, using `JIMotion.standard`. `reduceMotion` collapses the duration to
/// `JIMotion.press` rather than skipping the transition outright — content still
/// fades between tabs instead of flashing straight from one to the other.
public struct TabTransition<SelectionValue: Hashable, Content: View>: View {
    private let selection: SelectionValue
    private let content: (SelectionValue) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(selection: SelectionValue, @ViewBuilder content: @escaping (SelectionValue) -> Content) {
        self.selection = selection
        self.content = content
    }

    public var body: some View {
        ZStack {
            content(selection)
                .id(selection)
                .transition(.jiTabCrossfade)
        }
        // W-FIX2 BUG-16: this layer sits behind the chrome-only TabView, so the floating bar is
        // not in its safe area — add it, and every scroll's last control rests above the bar.
        // Backgrounds still run under the bar (the glass keeps sampling them).
        // `contentMargins` (environment, reaches every scroll view / List below, across the
        // per-tab NavigationStacks) — `safeAreaPadding` / `safeAreaInset` on this layer do not
        // cross the UIKit navigation boundary (sim-verified, W-FIX2).
        .contentMargins(.bottom, tabBarBottomClearance(sizeClass == .regular ? .regular : .compact), for: .scrollContent)
        .animation(reduceMotion ? JIMotion.press : JIMotion.standard, value: selection)
    }
}
