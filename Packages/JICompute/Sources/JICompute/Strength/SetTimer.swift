import Foundation

/// W-B38-A A-9 (gap #29/#31): the rest countdown between sets and the countdown of a timed set
/// (plank, carry). Pure value type — the caller passes `now` (JICompute never reads the clock).
public nonisolated struct SetTimer: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case idle, resting, timedSet }

    public private(set) var phase: Phase
    public private(set) var endsAt: Date?

    public init() { phase = .idle; endsAt = nil }

    public func startingRest(seconds: Int, at now: Date) -> SetTimer { start(.resting, seconds, now) }
    public func startingTimedSet(seconds: Int, at now: Date) -> SetTimer { start(.timedSet, seconds, now) }

    /// +30 s / −30 s on a running countdown (no-op when idle).
    public func adding(seconds: Int) -> SetTimer {
        guard phase != .idle, let endsAt else { return self }
        var next = self
        next.endsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
        return next
    }

    public func stopped() -> SetTimer { SetTimer() }

    /// Whole seconds left, rounded UP (a countdown shows "1" until it is really over), never
    /// below 0; nil when idle.
    public func remainingSeconds(at now: Date) -> Int? {
        guard phase != .idle, let endsAt else { return nil }
        return Int(max(0, endsAt.timeIntervalSince(now)).rounded(.up))
    }

    public func isFinished(at now: Date) -> Bool {
        guard phase != .idle, let endsAt else { return false }
        return now >= endsAt
    }

    private func start(_ phase: Phase, _ seconds: Int, _ now: Date) -> SetTimer {
        guard seconds > 0 else { return SetTimer() }
        var next = SetTimer()
        next.phase = phase
        next.endsAt = now.addingTimeInterval(TimeInterval(seconds))
        return next
    }
}
