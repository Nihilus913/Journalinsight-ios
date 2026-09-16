import SwiftUI

/// Reusable reveal choreography, generalized from `VerdictHeroView`'s hand-rolled
/// `revealed` state (feel diagnosis 2026-09-03): fades + rises in on **every**
/// `onAppear` (not just first load — a tab return replays it), resets on
/// `onDisappear` so the next appear replays cleanly.
///
/// `reduceMotion` suppresses the vertical offset entirely (opacity-only fallback,
/// per rule 4 — no scale/translation when Reduce Motion is on).
/// Pre-reveal opacity: `0` while hidden, `1` once revealed — identical in both
/// motion states (Reduce Motion only suppresses the *offset*, never the fade).
public nonisolated func revealOpacity(revealed: Bool) -> Double { revealed ? 1 : 0 }

/// Pre-reveal vertical offset. Reduce Motion suppresses it unconditionally (opacity-only
/// fallback, rule 4 — no scale/translation while Reduce Motion is on).
public nonisolated func revealOffsetY(revealed: Bool, reduceMotion: Bool, offset: CGFloat) -> CGFloat {
    reduceMotion ? 0 : (revealed ? 0 : offset)
}

public struct RevealChoreography: ViewModifier {
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let offset: CGFloat

    /// - Parameter offset: the pre-reveal vertical offset in points, applied only
    ///   when Reduce Motion is off. Defaults to `VerdictHeroView`'s original `12`.
    public init(offset: CGFloat = 12) {
        self.offset = offset
    }

    public func body(content: Content) -> some View {
        content
            .opacity(revealOpacity(revealed: revealed))
            .offset(y: revealOffsetY(revealed: revealed, reduceMotion: reduceMotion, offset: offset))
            .onAppear { withAnimation(reduceMotion ? nil : JIMotion.reveal) { revealed = true } }
            .onDisappear { revealed = false }
    }
}

public extension View {
    /// Applies the shared reveal choreography (opacity + rise-in, reduce-motion
    /// honored, replays on every appear). See `RevealChoreography`.
    func jiReveal(offset: CGFloat = 12) -> some View {
        modifier(RevealChoreography(offset: offset))
    }
}
