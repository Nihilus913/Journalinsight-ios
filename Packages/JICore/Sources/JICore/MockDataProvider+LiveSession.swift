import Foundation

/// W3b-L1 — dev/preview/test-only synthesized live-session feed. Deterministic (call-count keyed,
/// never wall-clock) so polling it repeatedly is reproducible: the profile climbs
/// under -> approaching -> breach, then recovers, so every `HrCapState` band is reachable without a
/// real workout — verbatim values from RN's `MockDataProvider.ts` `LIVE_SESSION_HR_PROFILE`.
private let liveSessionHRProfile: [Int] = [118, 128, 140, 152, 161, 168, 174, 179, 185, 176, 162, 148, 130]
private let liveSessionPollS = 2
private let liveSessionTargetLoad = 300.0

/// `MockDataProvider` (`MockDataProvider.swift`) is a frozen, stateless value type with no stored
/// tick counter of its own — this box is the only place that call-count state can live without
/// touching that frozen file. Guarded by `NSLock` (not an actor) so the synchronous, nonisolated
/// `liveSession()` below — matching every other JICore method's nonisolated, nonasync-context-free
/// call shape — can read/advance it without an `await`.
private final class LiveSessionTickBox: @unchecked Sendable {
    static let shared = LiveSessionTickBox()
    private let lock = NSLock()
    private var tick = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        defer { tick += 1 }
        return tick
    }
    func reset() { lock.lock(); defer { lock.unlock() }; tick = 0 }
}

extension MockDataProvider: LiveSessionProviding {
    public func liveSession() async throws -> LiveSessionSample {
        let idx = min(LiveSessionTickBox.shared.next(), liveSessionHRProfile.count - 1)
        return LiveSessionSample(
            hrBpm: liveSessionHRProfile[idx],
            elapsedS: idx * liveSessionPollS,
            load: min(liveSessionTargetLoad, Double(idx * 25)),
            targetLoad: liveSessionTargetLoad
        )
    }

    /// Test-only: rewinds the shared synthesized feed to the start of its profile so tests don't
    /// bleed tick state into one another (the feed is process-global, not per-instance, since the
    /// frozen `MockDataProvider` struct carries no identity to key a per-instance ticker on).
    public static func resetLiveSessionFeed() { LiveSessionTickBox.shared.reset() }
}
