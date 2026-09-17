import Foundation

/// Pure auto-end policy for the verdict Live Activity: no ActivityKit import,
/// so it is unit-testable outside the widget-extension sandbox (see
/// `Widgets/PolicyKit`, a standalone SwiftPM package that compiles this file
/// directly — never duplicate this logic there).
///
/// Per the W2 plan (2026-09-13-swift-w2-premium-bar.md, W2c-L3 row): the
/// activity auto-ends at session start's own end, or when either cap is hit:
/// 8h of active runtime, or 4h since the last update ("stale").
public enum LiveActivityCapPolicy {
    /// Total wall-clock time an activity may stay open after it starts.
    public static let activeCap: TimeInterval = 8 * 3600
    /// Time since the last `update(from:)` call before the activity is
    /// considered stale and force-ended.
    public static let staleCap: TimeInterval = 4 * 3600

    /// Whether an activity started at `startedAt`, last updated at
    /// `lastUpdateAt`, should be ended as of `now`.
    public static func shouldEnd(startedAt: Date, lastUpdateAt: Date, now: Date) -> Bool {
        guard now >= startedAt else { return false } // clock skew guard — never end retroactively
        let activeElapsed = now.timeIntervalSince(startedAt)
        let staleElapsed = now.timeIntervalSince(lastUpdateAt)
        return activeElapsed >= activeCap || staleElapsed >= staleCap
    }
}
