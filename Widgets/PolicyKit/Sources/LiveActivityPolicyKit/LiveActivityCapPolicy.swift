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

/// W-FIX7 F7-4: what to do with the verdict activities already running when the app (re)starts —
/// `Activity<…>.activities` survives an app relaunch, the controller's own reference does not.
/// Adopt the first active one; end every other active one (duplicates from earlier launches).
/// Ended / dismissed ones are never adopted — a finished day is not re-opened.
public enum LiveActivityAdoption {
    public struct Plan<ID: Hashable>: Equatable {
        public var adopt: ID?
        public var end: [ID]
    }

    /// B-21: `held` = the activity the controller already drives (nil after a relaunch). A verdict
    /// activity can now also be started REMOTELY (APNs push-to-start at Morning GO) while the app holds
    /// its own — keep the held one while it is still active (no flicker, it gets today's content on the
    /// same update) and end the extra; if the held one is gone, adopt the first active (e.g. the
    /// remotely-started card). Never a second card either way.
    public static func plan<ID: Hashable>(running: [(id: ID, isActive: Bool)], held: ID? = nil) -> Plan<ID> {
        let active = running.filter(\.isActive).map(\.id)
        if let held, active.contains(held) {
            return Plan(adopt: held, end: active.filter { $0 != held })
        }
        return Plan(adopt: active.first, end: Array(active.dropFirst()))
    }

    /// B-21: does the controller need to (re)run adoption? Yes when it holds nothing, or when an
    /// active verdict activity other than the held one exists (a push-to-start card appeared).
    public static func needsAdoption<ID: Hashable>(running: [(id: ID, isActive: Bool)], held: ID?) -> Bool {
        guard let held else { return true }
        return running.contains { $0.isActive && $0.id != held }
    }

    /// W-FIX7 fixer F7-4: the ended ("Done") cards still on the Lock Screen. Keep today's newest one
    /// (the day's "done" card), dismiss every other one at once; `dayFinished` = today already
    /// ended its activity, so no new card is requested for it (a finished day is not re-opened).
    public struct EndedPlan<ID: Hashable>: Equatable {
        public var keep: ID?
        public var dismiss: [ID]
        public var dayFinished: Bool { keep != nil }
    }

    public static func endedPlan<ID: Hashable>(ended: [(id: ID, lastUpdate: Date)], now: Date,
                                               calendar: Calendar = .current) -> EndedPlan<ID> {
        let today = ended.filter { calendar.isDate($0.lastUpdate, inSameDayAs: now) }
        let keep = today.max { $0.lastUpdate < $1.lastUpdate }?.id
        return EndedPlan(keep: keep, dismiss: ended.map(\.id).filter { $0 != keep })
    }
}
