import Foundation
import Observation
import JICore
import JICompute
import JIDesign

/// Live Session Coach view model (W3b-L1, P-session-coach). Oracle: `mobile/src/data/useLiveSession.ts`
/// + `mobile/src/lib/hrSafety.ts`. Polls `LiveSessionProviding.liveSession()` on a fixed interval
/// while the injected provider is capable, exactly like the RN hook's `setInterval` loop — plain
/// `Task` + `Task.sleep` rather than `SectionLoader`/`OfflineCache` (a live, ever-refreshing stream
/// has no cache key to restore from, mirrors the oracle's choice to skip react-query here too).
///
/// `provider` is `any HealthDataProvider` (not `any LiveSessionProviding` directly) so a caller can
/// hand this VM whatever provider instance the app is actually running against and let capability
/// be decided here, matching the RN gate's own shape (`hasSessionCapability(p.sessionCapabilities,
/// SessionCapability.LiveHr) && !!p.getLiveSession`). `nil` (no provider available to check) is
/// treated as not-capable — the same outcome a real `HubDataProvider` cast always produces today
/// (it deliberately never conforms — see `LiveSessionProviding.swift`), so a caller that cannot
/// yet thread its live provider through (e.g. `TrainingView`, which only holds `TrainingViewModel`
/// and has no accessor onto its private provider) is not lying by passing `nil`: the resulting
/// "not available" wall is the correct, honest state for every real hub connection this wave.
@Observable @MainActor
public final class SessionCoachViewModel {
    /// W-B38-A A-9: the cap rule now lives in `JICompute.SessionCap`; this VM delegates.
    public typealias CapState = SessionCap.State

    /// B-57 W4: the user's settings (optional cap, zones, Avoid Zone 5). Never changed by the app.
    public let settings: GateSettings
    public var hrCapBpm: Int? { settings.hrCapBpm }
    public var limitBpm: Int? { Self.limitBpm(settings) }

    /// The HR the session stays at or under: the cap and/or the top of Zone 4 when the user
    /// avoids Zone 5. nil = the user chose no limit at all.
    public nonisolated static func limitBpm(_ s: GateSettings) -> Int? {
        SessionCap.limitBpm(hrCapBpm: s.hrCapBpm, zone5FloorBpm: s.zone5FloorBpm)
    }

    /// `false` when the injected provider never conforms to `LiveSessionProviding` — the sole gate:
    /// the view renders the "not available" wall instead of polling, and this VM never calls
    /// `liveSession()` when this is false.
    public private(set) var capable: Bool
    public private(set) var sample: LiveSessionSample?
    /// Set whenever a poll tick throws; `sample` deliberately keeps its last-good value so a poll
    /// failure never presents a frozen reading as if it were still live (the banner is the signal).
    public private(set) var error: String?
    /// `true` once the first poll has answered (success or failure) — the difference between
    /// "waiting for the first reading" (`.loading`) and a genuine gap.
    public private(set) var hasPolled = false

    /// W8-L4: DESIGN-7 `ScreenState`. `capable == false` → `.empty` (the "not available" wall — no
    /// loading spinner for a provider that will never answer); a poll error → `.error` even while
    /// `sample` keeps its last-good value (the banner is the honesty signal, see `error`).
    public var screenState: ScreenState {
        guard capable else { return .empty }
        if let error { return .error(error) }
        if sample != nil { return .loaded }
        return hasPolled ? .empty : .loading
    }

    private let liveProvider: (any LiveSessionProviding)?
    private let pollNs: UInt64
    /// W-B31 R-1: the haptics dispatcher the HR-cap edge fires through (`.shared` in the app; a
    /// private one per test).
    private let haptics: JIHapticDispatcher
    /// The cap state after the previous tick (nil before the first one) — RN `SessionCoach.tsx`
    /// `prevCapState` ref.
    private var prevCapState: JIHrCapState?
    private var pollTask: Task<Void, Never>?

    public convenience init(provider: (any HealthDataProvider)?, pollIntervalMs: UInt64 = 2000, settings: GateSettings = GateSettings()) {
        self.init(live: provider as? any LiveSessionProviding, pollIntervalMs: pollIntervalMs, settings: settings)
    }

    /// W-B38-B B-8: a live source handed in directly — the phone's `MirroredSessionFeed` (the Watch's
    /// mirrored strength session). `mirrored` is set when it is that feed, so the screen also lists
    /// the sets as they land.
    public init(live: (any LiveSessionProviding)?, pollIntervalMs: UInt64 = 2000, settings: GateSettings = GateSettings(),
                haptics: JIHapticDispatcher = .shared) {
        self.settings = settings
        self.haptics = haptics
        self.liveProvider = live
        self.mirrored = live as? MirroredSessionFeed
        self.capable = live != nil
        self.pollNs = pollIntervalMs * 1_000_000
    }

    /// B-8: the mirrored Watch session (sets, current exercise), nil for any other source.
    public let mirrored: MirroredSessionFeed?

    /// Idempotent — a second call while already polling is a no-op (mirrors the oracle's effect
    /// running once per mount, not re-arming on every render).
    public func start() {
        guard capable, let liveProvider, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                guard let pollNs = self?.pollNs else { return }
                try? await Task.sleep(nanoseconds: pollNs)
            }
        }
    }

    /// Called from the view's `.onDisappear` — cancels the poll loop so it never keeps ticking
    /// after the screen is gone (exit criterion: "polling stops on disappear").
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One poll tick (internal for the haptics tests, which drive ticks directly).
    func tick() async {
        guard let provider = liveProvider else { return }
        defer { hasPolled = true }
        do {
            let next = try await provider.liveSession()
            sample = next
            error = nil
        } catch {
            self.error = (error as? HubError).map(Self.describe) ?? error.localizedDescription
        }
        fireCapEdgeHaptic()
    }

    /// RN `SessionCoach.tsx` L145–156: on a real cap-state edge, `hapticGateChange(tier)` —
    /// breach = "failed" (even from the first reading), any other real transition = "changed",
    /// no edge / to-or-from unknown = nothing.
    private func fireCapEdgeHaptic() {
        let next = Self.hapticCapState(capState)
        defer { prevCapState = next }
        if let tier = JIHapticRecipes.gateChangeTier(prevCap: prevCapState, nextCap: next) {
            haptics.fire(.gateChange(tier))
        }
    }

    /// `CapState` → the haptics layer's `JIHrCapState`, case-for-case. `.noLimit` → `.unknown`:
    /// no limit is never haptic-worthy (RN's null cap).
    nonisolated static func hapticCapState(_ state: CapState) -> JIHrCapState {
        switch state {
        case .unknown, .noLimit: .unknown
        case .under: .under
        case .approaching: .approaching
        case .breach: .breach
        }
    }

    public var capState: CapState { Self.deriveCapState(hrBpm: sample?.hrBpm, limitBpm: limitBpm) }

    public var elapsedText: String {
        guard let s = sample?.elapsedS else { return "—" }
        return DurationFormat.clock(seconds: s)
    }

    public var loadProgress: Double {
        guard let sample, sample.targetLoad > 0 else { return 0 }
        return max(0, min(1, sample.load / sample.targetLoad))
    }

    /// Port of `deriveHrCapState` (`mobile/src/lib/hrSafety.ts`) — delegates to `SessionCap`.
    public nonisolated static func deriveCapState(hrBpm: Int?, limitBpm: Int?) -> CapState {
        SessionCap.state(hrBpm: hrBpm, limitBpm: limitBpm)
    }

    public nonisolated static func tone(for state: CapState) -> VerdictTone {
        switch state {
        case .unknown, .noLimit: .muted
        case .under: .go
        case .approaching: .amber
        case .breach: .red
        }
    }

    public nonisolated static func label(for state: CapState) -> String { SessionCap.label(for: state) }

    /// E15-5 port — every band (including "under") ships one concrete next action, never a bare
    /// warning. Delegates to `SessionCap`.
    public nonisolated static func action(for state: CapState, settings: GateSettings) -> String {
        let zone5 = settings.zone5FloorBpm != nil ? (settings.zones?.rangeText(5) ?? "—") : nil
        return SessionCap.action(for: state, limitBpm: limitBpm(settings), zone5RangeText: zone5)
    }

    private static func describe(_ error: HubError) -> String {
        switch error {
        case .unauthorized: "Hub rejected the token."
        case .network(let detail): detail
        case .http(_, let detail): detail ?? "Live session unavailable"
        case .decoding(let detail): detail
        case .duplicate(let detail), .yazioAuthExpired(let detail): detail
        }
    }
}
