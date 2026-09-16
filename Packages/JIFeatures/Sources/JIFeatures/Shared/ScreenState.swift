import Foundation
import JICore

/// Screen-level state (DESIGN-7): a strict refinement of `TodayViewModel.Phase`, not a second state
/// machine. `resolve(...)` is a pure function of the same signals `TodayViewModel` already tracks
/// (the phase it already computed, whether any section has ever synced before, the morning verdict's
/// date, and the latest section error) — so `phase` and `screenState` can never disagree about the
/// same fetch, and there is exactly one place (`TodayViewModel.fetchLive`) that decides the outcome.
///
/// Kept as its own type rather than adding cases straight into `Phase`: `Phase` is matched exhaustively
/// by call sites outside this lane's file list, and extending it here — rather than just adding new
/// cases nobody asked those call sites to switch over — would be a breaking, not additive, change this
/// wave. `ScreenState` layers the extra detail on top instead.
nonisolated public enum ScreenState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    /// The hub answered fine and there is genuinely no history — no section has ever synced before
    /// this attempt, and this attempt came back with no verdict and no recovery days. Distinct from
    /// `.empty`, which is a transient blank spell on a screen that has synced successfully before.
    case neverSynced
    /// `morning.verdictDate` is present but isn't today — the hub answered, but the verdict it
    /// returned was computed for an earlier day (a missed or delayed sync). Carries that date for the
    /// banner copy.
    case staleVerdictDate(String)
    /// A section reported `HubError.yazioAuthExpired` — a named UI contract (CLAUDE.md rule 4), always
    /// surfaced regardless of what the other sections did, never flattened into a generic error card.
    case yazioAuthExpired(detail: String)
    case error(String)

    public static func resolve(
        phase: TodayViewModel.Phase,
        neverSynced: Bool,
        verdictDate: String?,
        todayDateString: String,
        lastError: HubError?
    ) -> ScreenState {
        if case .yazioAuthExpired(let detail) = lastError { return .yazioAuthExpired(detail: detail) }
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .error(let message): return .error(message)
        case .empty: return neverSynced ? .neverSynced : .empty
        case .loaded:
            if let verdictDate, verdictDate != todayDateString { return .staleVerdictDate(verdictDate) }
            return .loaded
        }
    }
}
