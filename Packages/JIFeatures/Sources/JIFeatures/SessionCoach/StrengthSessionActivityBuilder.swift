import Foundation
import JICore

/// W-B38-B B-7 — builds the strength Live Activity's `StrengthSessionActivityState` from what the
/// phone knows (mirrored Watch session + the set just logged). The cap band uses the SAME rule as
/// the Session Coach (`SessionCoachViewModel.deriveCapState` against the user's own limit — the
/// cap and/or the top of Zone 4 when Zone 5 is avoided), so every HR surface agrees.
public nonisolated enum StrengthSessionActivityBuilder {
    public static func state(exercise: String, setNumber: Int, setCount: Int? = nil, weightKg: Double? = nil,
                             reps: Int? = nil, durationS: Int? = nil, restS: Int? = nil, hrBpm: Int?,
                             settings: GateSettings, now: Date) -> StrengthSessionActivityState {
        let limit = SessionCoachViewModel.limitBpm(settings)
        let resting = (restS ?? 0) > 0
        return StrengthSessionActivityState(
            exercise: exercise, setNumber: setNumber, setCount: setCount, weightKg: weightKg, reps: reps,
            durationS: durationS,
            restStartedAt: resting ? now : nil,
            restEndsAt: resting ? now.addingTimeInterval(TimeInterval(restS ?? 0)) : nil,
            hrBpm: hrBpm, limitBpm: limit,
            capBand: band(SessionCoachViewModel.deriveCapState(hrBpm: hrBpm, limitBpm: limit)),
            updatedAt: now)
    }

    public static func band(_ s: SessionCoachViewModel.CapState) -> StrengthSessionActivityState.CapBand {
        switch s {
        case .unknown: .unknown
        case .noLimit: .noLimit
        case .under: .under
        case .approaching: .approaching
        case .breach: .breach
        }
    }
}
