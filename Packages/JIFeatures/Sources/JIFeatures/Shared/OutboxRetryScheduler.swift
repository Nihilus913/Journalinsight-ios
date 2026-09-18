import Foundation
import Observation
import JIPersistence
#if canImport(BackgroundTasks) && !os(watchOS) && !os(macOS)
import BackgroundTasks
#endif

/// Seam over `BGTaskScheduler` so `OutboxRetryScheduler` can be tested with a fake that simply
/// fires the registered handler on demand (the exit criterion's "simulated BG refresh"). The real
/// adapter is `BGTaskSchedulerAdapter` below.
public nonisolated protocol BackgroundRefreshScheduling: Sendable {
    /// Registers `handler` as the launch body for `identifier`. Must be called before the app
    /// finishes launching (BGTaskScheduler's rule). Returns `false` when the identifier isn't in
    /// `BGTaskSchedulerPermittedIdentifiers` (or registration failed) — the scheduler then runs
    /// foreground-only.
    func register(identifier: String, handler: @escaping @Sendable () async -> Bool) -> Bool
    /// Asks the OS for one app-refresh launch no earlier than `earliestBeginDate` (`nil` = ASAP).
    func submitRefresh(identifier: String, earliestBeginDate: Date?) throws
    func cancelRefresh(identifier: String)
}

/// Foreground periodic retry with backoff + `BGAppRefreshTask` for the `Outbox` (W8-L4,
/// P-hub-watchdog / P-weigh-in). Three triggers, all funnelling into `OutboxDrainer.drainOnce()`:
///
/// 1. `startForeground()` — a loop that drains, then sleeps `backoff.delay(attempt:)` while rows
///    remain pending (30 s → 60 s → … capped at 15 min) and `idleInterval` while the outbox is
///    empty (a cheap local read that catches rows enqueued later without any VM having to know
///    this scheduler exists). `stopForeground()` (scene → background) cancels the loop and, if
///    rows remain, books a BG refresh so the retry outlives the foreground.
/// 2. `handleBackgroundRefresh()` — the BG task body: one drain pass, then re-book itself with the
///    same backoff while anything is still pending.
/// 3. `HubWatchdog.onReachableAgain` (W7-L4) keeps calling `drainOnForeground()` directly — the
///    reachable-again transition is the earliest honest signal and is not delayed by backoff.
///
/// `drainer` is resolved lazily through `drainerSource` because the hub provider (and with it a
/// usable drainer) only exists once a connection does, while `registerBackgroundTask()` has to run
/// before the app finishes launching.
@Observable @MainActor
public final class OutboxRetryScheduler {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in `project.yml` (→ `App/Info.plist`).
    public nonisolated static let refreshTaskIdentifier = "toby913.JournalInsight.outboxRefresh"

    /// Exponential backoff with a hard cap: `base × factor^(attempt-1)`, never above `cap`.
    public nonisolated struct Backoff: Sendable, Equatable {
        public var base: Duration
        public var factor: Double
        public var cap: Duration

        public init(base: Duration, factor: Double, cap: Duration) {
            self.base = base
            self.factor = factor
            self.cap = cap
        }

        public static let `default` = Backoff(base: .seconds(30), factor: 2, cap: .seconds(15 * 60))

        /// `attempt` is 1-based (the delay AFTER the n-th consecutive pass that left rows pending);
        /// anything below 1 is treated as 1.
        public func delay(attempt: Int) -> Duration {
            let exponent = max(attempt, 1) - 1
            let baseSeconds = Double(base.components.seconds) + Double(base.components.attoseconds) / 1e18
            let capSeconds = Double(cap.components.seconds) + Double(cap.components.attoseconds) / 1e18
            let raw = baseSeconds * pow(factor, Double(exponent))
            return .seconds(min(raw, capSeconds))
        }
    }

    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// Consecutive foreground/BG passes that ended with rows still pending; `0` once a pass
    /// leaves the outbox empty. Drives the next delay.
    public private(set) var consecutiveIncompletePasses = 0
    /// Whether `registerBackgroundTask()` succeeded — `false` also when no scheduler was injected.
    public private(set) var backgroundRegistered = false
    public private(set) var isForegroundLoopRunning = false

    public let backoff: Backoff
    /// Sleep between passes while nothing is pending (a local `pending()` read, no network).
    public let idleInterval: Duration

    private let drainerSource: @MainActor () -> OutboxDrainer?
    private let background: (any BackgroundRefreshScheduling)?
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private var loop: Task<Void, Never>?

    /// - Parameters:
    ///   - drainerSource: resolved on every pass; `nil` (no connection yet) makes a pass a no-op
    ///     that still counts as "nothing pending" for backoff purposes.
    ///   - background: `nil` = foreground-only (previews, tests that don't care).
    ///   - sleep: injected so tests can record the requested delays instead of waiting.
    public init(
        drainerSource: @escaping @MainActor () -> OutboxDrainer?,
        background: (any BackgroundRefreshScheduling)?,
        backoff: Backoff = .default,
        idleInterval: Duration = .seconds(5 * 60),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.drainerSource = drainerSource
        self.background = background
        self.backoff = backoff
        self.idleInterval = idleInterval
        self.sleep = sleep
        self.now = now
    }

    public convenience init(drainer: OutboxDrainer, background: (any BackgroundRefreshScheduling)?, backoff: Backoff = .default, idleInterval: Duration = .seconds(5 * 60), sleep: @escaping Sleep = { try await Task.sleep(for: $0) }, now: @escaping @Sendable () -> Date = Date.init) {
        self.init(drainerSource: { drainer }, background: background, backoff: backoff, idleInterval: idleInterval, sleep: sleep, now: now)
    }

    // MARK: - Background task

    /// Call once, before the app finishes launching (SwiftUI: the `App`'s `init`). Idempotent.
    @discardableResult
    public func registerBackgroundTask() -> Bool {
        guard !backgroundRegistered, let background else { return backgroundRegistered }
        backgroundRegistered = background.register(identifier: Self.refreshTaskIdentifier) { [weak self] in
            guard let self else { return false }
            return await self.handleBackgroundRefresh()
        }
        return backgroundRegistered
    }

    /// The BG-refresh body. One drain pass; re-books itself (with backoff) while rows remain.
    /// Returns `false` only when the pass delivered nothing AND rows are still pending — the
    /// signal BGTaskScheduler uses to throttle a task that keeps failing.
    @discardableResult
    public func handleBackgroundRefresh() async -> Bool {
        let outcome = await pass()
        if outcome.remaining > 0 { scheduleBackgroundRefresh(after: nextDelay()) }
        return outcome.delivered > 0 || outcome.remaining == 0
    }

    /// Books (or re-books) the refresh for `delay` from now. Safe to call when unregistered — it
    /// then does nothing, and the foreground loop remains the only retry.
    public func scheduleBackgroundRefresh(after delay: Duration) {
        guard backgroundRegistered, let background else { return }
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        try? background.submitRefresh(identifier: Self.refreshTaskIdentifier, earliestBeginDate: now().addingTimeInterval(seconds))
    }

    // MARK: - Foreground loop

    /// Idempotent — a second call while the loop runs is a no-op.
    public func startForeground() {
        guard loop == nil else { return }
        isForegroundLoopRunning = true
        background?.cancelRefresh(identifier: Self.refreshTaskIdentifier)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.foregroundTick()
                do { try await self.sleep(delay) } catch { break }
            }
            self?.loop = nil
            self?.isForegroundLoopRunning = false
        }
    }

    /// Cancels the loop; if rows remain, hands over to a BG refresh at the current backoff.
    public func stopForeground() {
        loop?.cancel()
        loop = nil
        isForegroundLoopRunning = false
        if (drainerSource()?.pendingDeliverableCount() ?? 0) > 0 {
            scheduleBackgroundRefresh(after: nextDelay())
        }
    }

    /// One foreground pass; returns how long the loop should sleep before the next one. Exposed so
    /// tests can step the loop deterministically.
    @discardableResult
    public func foregroundTick() async -> Duration {
        let outcome = await pass()
        return outcome.remaining == 0 ? idleInterval : nextDelay()
    }

    /// The delay the current failure streak calls for (`backoff.delay(attempt: streak)`), or
    /// `backoff.base` when the streak is 0.
    public func nextDelay() -> Duration {
        backoff.delay(attempt: max(consecutiveIncompletePasses, 1))
    }

    // MARK: - Shared pass

    private struct PassOutcome { var delivered: Int; var remaining: Int }

    private func pass() async -> PassOutcome {
        guard let drainer = drainerSource() else {
            consecutiveIncompletePasses = 0
            return PassOutcome(delivered: 0, remaining: 0)
        }
        let results = await drainer.drainOnce()
        let delivered = results.values.filter { if case .success = $0 { true } else { false } }.count
        let remaining = drainer.pendingDeliverableCount()
        consecutiveIncompletePasses = remaining == 0 ? 0 : consecutiveIncompletePasses + 1
        return PassOutcome(delivered: delivered, remaining: remaining)
    }
}

#if canImport(BackgroundTasks) && !os(watchOS) && !os(macOS)
/// The production `BackgroundRefreshScheduling` over `BGTaskScheduler.shared`.
public nonisolated struct BGTaskSchedulerAdapter: BackgroundRefreshScheduling {
    public init() {}

    public func register(identifier: String, handler: @escaping @Sendable () async -> Bool) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // `BGTask` is not `Sendable`; the box is only ever touched from this launch handler's
            // own `Task` and its expiration handler, both of which BackgroundTasks serialises.
            let box = BGTaskBox(task)
            let work = Task {
                let ok = await handler()
                box.task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    public func submitRefresh(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    public func cancelRefresh(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

// @unchecked: see the comment in `BGTaskSchedulerAdapter.register` — single-owner hand-off of a
// non-Sendable `BGTask` between the launch handler's `Task` and its expiration handler.
private nonisolated final class BGTaskBox: @unchecked Sendable {
    let task: BGTask
    init(_ task: BGTask) { self.task = task }
}
#endif
