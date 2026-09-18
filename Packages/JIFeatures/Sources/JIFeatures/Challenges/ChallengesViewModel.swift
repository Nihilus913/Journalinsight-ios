import Foundation
import Observation
import JICore

/// Challenges screen view model (W3b-L3). Simpler than `TrainingViewModel`'s multi-section load —
/// this screen has exactly one section (the challenge list) and no `OfflineCache` dependency (not
/// in this lane's `consumes`), so it skips `SectionLoader`/cache-restore entirely and just tracks
/// a plain `Phase` (mirrors `TodayViewModel.Phase`'s shape for `ScreenState.resolve` compatibility,
/// though this screen doesn't need the verdict-date staleness cases).
@Observable @MainActor
public final class ChallengesViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var challenges: [GateChallenge] = []
    public private(set) var lastError: HubError?
    /// W7-L4 (P-hub-watchdog): the `TodayViewModel.hubReachable` idiom, replicated here rather than
    /// centralised — Challenges was the one screen VM without it, so a hub outage blanked the list
    /// with a bare "Couldn't load challenges." instead of the last known challenges plus an honest
    /// banner. `false` means a genuine `HubError.network` ONLY; a 401 is a token problem and stays
    /// `true` (see `StalenessBanner`'s doc comment — routing `.unauthorized` through this flag is
    /// the PARITY-3 bug it warns about).
    public private(set) var hubReachable = true
    /// When `challenges` was last fetched successfully — `nil` until one fetch has landed. Feeds
    /// `StalenessBanner`, which shows nothing without it (never a banner claiming staleness for
    /// data that was never there).
    public private(set) var fetchedAt: Date?

    private let provider: any ChallengesProviding
    private let now: () -> Date

    public init(provider: any ChallengesProviding, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    /// Oracle `app/challenges.tsx`'s `active`/`past` split.
    public var active: [GateChallenge] { challenges.filter { $0.status == .active } }
    public var past: [GateChallenge] { challenges.filter { $0.status != .active } }

    public func load() async {
        phase = .loading
        await refresh()
    }

    public func refresh() async {
        do {
            let rows = try await provider.challenges()
            challenges = rows
            lastError = nil
            hubReachable = true
            fetchedAt = now()
            phase = rows.isEmpty ? .empty : .loaded
        } catch {
            let hubError = asHubError(error)
            lastError = hubError
            // Same branching as `TodayViewModel.fetchLive`: only `.network` clears `hubReachable`,
            // and a screen that already has rows keeps showing them (`.loaded` + banner) rather
            // than collapsing to an error card — blank is not honest when we hold real data.
            switch hubError {
            case .network:
                hubReachable = false
                phase = challenges.isEmpty ? .error(Self.describe(error)) : .loaded
            default:
                hubReachable = true
                phase = challenges.isEmpty ? .error(Self.describe(error)) : .loaded
            }
        }
    }

    /// Returns the created row on success (never zero'd — the hub's real `challenge_id`), or the
    /// named `HubError` on failure so the create form can surface it.
    @discardableResult
    public func create(_ input: ChallengeCreateInput) async -> Result<GateChallenge, HubError> {
        do {
            let created = try await provider.createChallenge(input)
            challenges.append(created)
            return .success(created)
        } catch {
            return .failure(asHubError(error))
        }
    }

    @discardableResult
    public func update(challengeId: Int, patch: ChallengeUpdatePatch) async -> Result<GateChallenge, HubError> {
        do {
            let updated = try await provider.updateChallenge(challengeId: challengeId, patch: patch)
            replace(updated)
            return .success(updated)
        } catch {
            return .failure(asHubError(error))
        }
    }

    @discardableResult
    public func archive(challengeId: Int, status: ChallengeArchiveStatus, resultNote: String?) async -> Result<GateChallenge, HubError> {
        do {
            let updated = try await provider.archiveChallenge(challengeId: challengeId, status: status, resultNote: resultNote)
            replace(updated)
            return .success(updated)
        } catch {
            return .failure(asHubError(error))
        }
    }

    @discardableResult
    public func delete(challengeId: Int) async -> HubError? {
        do {
            try await provider.deleteChallenge(challengeId: challengeId)
            challenges.removeAll { $0.challengeId == challengeId }
            return nil
        } catch {
            return asHubError(error)
        }
    }

    private func replace(_ updated: GateChallenge) {
        if let idx = challenges.firstIndex(where: { $0.challengeId == updated.challengeId }) {
            challenges[idx] = updated
        } else {
            challenges.append(updated)
        }
    }

    private func asHubError(_ error: Error) -> HubError { (error as? HubError) ?? .decoding("\(error)") }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}

/// Oracle `describeChallengeMutationError` (`app/challenges.tsx`): any hub-supplied `detail` (the
/// 422 locked-field message, the 409 "archive it instead" message) is surfaced verbatim; anything
/// else falls back to a generic retry prompt. Never a raw `.localizedDescription` dump.
public nonisolated func describeChallengeMutationError(_ error: HubError) -> String {
    switch error {
    case .network: "Can't save while offline — try again once you're back online."
    case .http(_, let detail): detail ?? "Couldn't save — try again."
    case .duplicate(let detail): detail.isEmpty ? "Couldn't save — try again." : detail
    case .unauthorized: "Hub rejected the token — check Settings › Connection."
    case .yazioAuthExpired(let detail): detail
    case .decoding: "Couldn't save — try again."
    }
}
