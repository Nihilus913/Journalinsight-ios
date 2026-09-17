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

    private let provider: any ChallengesProviding

    public init(provider: any ChallengesProviding) {
        self.provider = provider
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
            phase = rows.isEmpty ? .empty : .loaded
        } catch {
            lastError = asHubError(error)
            phase = .error(Self.describe(error))
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
