import Foundation
import Observation
import JICore
import JIPersistence

/// W4-L3 (P-goals), mirrors `mobile/app/goals-setup.tsx` + `mobile/src/data/useGoals.ts`'s
/// `useGoals`/`useUpdateGoals`. Reads through the frozen `EnergyProviding.goals()` (the same
/// `GET /planning/goals` route the Energy tab already calls); writes through the new
/// `GoalsProviding.updateGoals` (`PUT /planning/goals`). On a successful save, the result is also
/// written into `GoalStore`'s `goal_targets_mirror` (local-first mirror, R6c-3a) so it never
/// drifts stale relative to what was actually shown/edited.
@Observable @MainActor
public final class GoalsSetupViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, saving, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var goals: Goals?
    public private(set) var savedAt: Date?

    private let provider: any GoalsSetupProviding
    private let goalStore: GoalStore?
    private let now: () -> Date

    public init(provider: any GoalsSetupProviding, goalStore: GoalStore? = nil, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.goalStore = goalStore
        self.now = now
    }

    public func load() async {
        phase = .loading
        do {
            let result = try await provider.goals()
            goals = result
            phase = .loaded
        } catch {
            phase = .error(Self.describe(error))
        }
    }

    /// Applies `patch` via `PUT /planning/goals`; on success the server's full document replaces
    /// `goals` (never the local optimistic merge — same "server is source of truth" rule as the
    /// RN oracle's `onSuccess`) and is upserted into `goal_targets_mirror`.
    @discardableResult
    public func save(_ patch: GoalsUpdate) async -> Bool {
        savedAt = nil
        phase = .saving
        do {
            let result = try await provider.updateGoals(patch)
            goals = result
            try? goalStore?.saveGoalTargetsMirror(result, now: now())
            savedAt = now()
            phase = .loaded
            return true
        } catch {
            phase = .error(Self.describe(error))
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}
