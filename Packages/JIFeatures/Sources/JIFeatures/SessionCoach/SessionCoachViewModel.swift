import Foundation
import Observation
import JICore

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
    public enum CapState: Equatable, Sendable { case unknown, under, approaching, breach }

    public nonisolated static let hrSafetyCapBpm = 175
    public nonisolated static let hrForbiddenZoneLowBpm = 176
    public nonisolated static let hrForbiddenZoneHighBpm = 198
    private nonisolated static let approachingBandBpm = 15

    /// `false` when the injected provider never conforms to `LiveSessionProviding` — the sole gate:
    /// the view renders the "not available" wall instead of polling, and this VM never calls
    /// `liveSession()` when this is false.
    public private(set) var capable: Bool
    public private(set) var sample: LiveSessionSample?
    /// Set whenever a poll tick throws; `sample` deliberately keeps its last-good value so a poll
    /// failure never presents a frozen reading as if it were still live (the banner is the signal).
    public private(set) var error: String?

    private let liveProvider: (any LiveSessionProviding)?
    private let pollNs: UInt64
    private var pollTask: Task<Void, Never>?

    public init(provider: (any HealthDataProvider)?, pollIntervalMs: UInt64 = 2000) {
        let live = provider as? any LiveSessionProviding
        self.liveProvider = live
        self.capable = live != nil
        self.pollNs = pollIntervalMs * 1_000_000
    }

    /// Idempotent — a second call while already polling is a no-op (mirrors the oracle's effect
    /// running once per mount, not re-arming on every render).
    public func start() {
        guard capable, let liveProvider, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(liveProvider)
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

    private func tick(_ provider: any LiveSessionProviding) async {
        do {
            let next = try await provider.liveSession()
            sample = next
            error = nil
        } catch {
            self.error = (error as? HubError).map(Self.describe) ?? error.localizedDescription
        }
    }

    public var capState: CapState { Self.deriveCapState(hrBpm: sample?.hrBpm) }

    public var elapsedText: String {
        guard let s = sample?.elapsedS else { return "—" }
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    public var loadProgress: Double {
        guard let sample, sample.targetLoad > 0 else { return 0 }
        return max(0, min(1, sample.load / sample.targetLoad))
    }

    /// Port of `deriveHrCapState` (`mobile/src/lib/hrSafety.ts`): `nil` always reads as `.unknown`,
    /// never a false "under" all-clear.
    public nonisolated static func deriveCapState(hrBpm: Int?) -> CapState {
        guard let hrBpm else { return .unknown }
        if hrBpm > hrSafetyCapBpm { return .breach }
        if hrBpm >= hrSafetyCapBpm - approachingBandBpm { return .approaching }
        return .under
    }

    public nonisolated static func tone(for state: CapState) -> VerdictTone {
        switch state {
        case .unknown: .muted
        case .under: .go
        case .approaching: .amber
        case .breach: .red
        }
    }

    public nonisolated static func label(for state: CapState) -> String {
        switch state {
        case .unknown: "No live reading"
        case .under: "Under cap"
        case .approaching: "Approaching cap"
        case .breach: "OVER CAP"
        }
    }

    /// E15-5 port — every band (including "under") ships one concrete next action, never a bare
    /// warning.
    public nonisolated static func action(for state: CapState) -> String {
        switch state {
        case .unknown: "No live heart-rate reading for this session — pace/RPE only."
        case .under: "On plan — hold pace."
        case .approaching: "Within \(approachingBandBpm) bpm of the \(hrSafetyCapBpm) cap — ease off before you reach it."
        case .breach: "Over the \(hrSafetyCapBpm) cap — Zone 5 (\(hrForbiddenZoneLowBpm)-\(hrForbiddenZoneHighBpm)) is forbidden. Back off now."
        }
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
