import Foundation
#if canImport(Network)
import Network
#endif

/// B-52 p1 (c): fires `onRegain` when the device's network path goes from unusable to usable —
/// the moment a write queued in a tunnel / on flight mode can go out, without waiting for the
/// watchdog's next probe or the retry scheduler's backoff. Foreground is the other trigger
/// (`JournalInsightApp`'s scene-phase site → `OutboxRetryScheduler.startForeground`, whose first
/// tick drains immediately).
///
/// The edge logic (`observe(satisfied:)`) is separate from `NWPathMonitor` so it is unit-testable:
/// the first observation only seeds the state (launch is the foreground trigger's job), and only a
/// false → true edge fires.
@MainActor
public final class ReachabilityDrainTrigger {
    public var onRegain: (@MainActor () async -> Void)?
    public private(set) var satisfied: Bool?
    public private(set) var regainCount = 0
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    public init(onRegain: (@MainActor () async -> Void)? = nil) { self.onRegain = onRegain }

    /// Feeds one path observation; returns true when it was a regain edge (and `onRegain` ran).
    @discardableResult
    public func observe(satisfied now: Bool) async -> Bool {
        let was = satisfied
        satisfied = now
        guard was == false, now else { return false }
        regainCount += 1
        await onRegain?()
        return true
    }

    public func start() {
        #if canImport(Network)
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in await self?.observe(satisfied: ok) }
        }
        m.start(queue: DispatchQueue(label: "ji.reachability"))
        monitor = m
        #endif
    }

    public func stop() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
        satisfied = nil
    }
}
