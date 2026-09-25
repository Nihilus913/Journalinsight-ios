import Foundation
import Observation
import JICore

/// Liveness probe for the hub (W7-L4, P-hub-watchdog): the one place that answers "is the Mac
/// awake and reachable right now?" independently of whether any screen happens to be fetching.
///
/// Why a separate probe rather than reusing a data fetch's outcome: a screen sitting on a warm
/// cache makes no requests at all, so without this the app can look healthy for minutes after the
/// hub has gone away — the exact dishonesty CLAUDE.md rule 5 forbids. The probe deliberately hits
/// `GET /health` only (unauthenticated on the hub — `app/main.py:75–79`), never a data route, so
/// it can never mutate, cache, or cost a real query; and it never piggybacks on a data fetch, so
/// per-screen `hubReachable` flags (e.g. `TodayViewModel`) stay exactly as they
/// are — this is an additional signal, not a replacement for them.
///
/// `reachable` starts `true`: the app has no evidence of an outage before its first probe, and
/// opening every screen with an "unreachable" banner that then vanishes would be its own lie.
@MainActor
@Observable
public final class HubWatchdog {
    /// `false` once a probe has failed for ANY reason (timeout, non-200, decode). `/health` takes
    /// no token, so unlike a data route there is no 401 case to exclude here — a `/health` that
    /// does not answer 200 means the hub is not serving, full stop.
    public private(set) var reachable = true
    /// When the last successful probe completed; `nil` until one has.
    public private(set) var lastOk: Date?
    /// The typed error from the most recent failed probe; cleared on the next success.
    public private(set) var lastError: HubError?

    /// Called on every false → true transition, on the main actor. W7-L4 hooks
    /// `OutboxDrainer.drainOnForeground()` here: the moment the hub comes back is exactly when a
    /// weigh-in queued while offline should be retried. Not called for the first successful probe
    /// of a session (no outage was ever observed), and not called for success-after-success.
    public var onReachableAgain: (@MainActor () async -> Void)?

    private let provider: any HealthDataProvider
    private let interval: Duration
    private let now: () -> Date
    private var loop: Task<Void, Never>?

    /// - Parameters:
    ///   - provider: probed via `HealthDataProvider.health()` — `HubDataProvider` in the app, a
    ///     stub-session-backed one in tests.
    ///   - interval: probe period while active. Defaults to `Staleness.hubQueryStaleTime` so the
    ///     watchdog and the staleness floor are the same number by construction (tests inject a
    ///     short one).
    ///   - now: injected clock — nothing here reads an ambient `Date()`.
    public init(
        provider: any HealthDataProvider,
        interval: Duration = .seconds(Staleness.hubQueryStaleTime),
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.interval = interval
        self.now = now
    }

    // No `deinit { loop?.cancel() }`: a nonisolated `deinit` may not touch `@MainActor` state under
    // Swift 6 strict concurrency, and it isn't needed — the loop holds `self` weakly, so it returns
    // on its next tick once the watchdog is gone. `stop()` is the prompt path.

    /// Probes immediately, then every `interval` until `stop()`. Idempotent: calling `start()`
    /// while already running restarts the cycle with a fresh immediate probe, which is what a
    /// foreground transition wants (the app has been asleep; re-check now, don't wait out the
    /// remainder of a period that elapsed in the background).
    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.probe()
                do { try await Task.sleep(for: self.interval) } catch { return }
            }
        }
    }

    /// Stops probing (scene phase left `.active`). Leaves `reachable`/`lastOk`/`lastError` as they
    /// were — a backgrounded app keeps its last honest reading rather than resetting to optimism.
    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// One probe. Public so the scene-phase hook can force an immediate check and so tests can
    /// drive transitions without waiting on a timer.
    @discardableResult
    public func probe() async -> Bool {
        let wasReachable = reachable
        do {
            _ = try await provider.health()
            reachable = true
            lastOk = now()
            lastError = nil
            if !wasReachable { await onReachableAgain?() }
            return true
        } catch {
            reachable = false
            lastError = (error as? HubError) ?? .decoding("\(error)")
            return false
        }
    }
}
