import SwiftUI
import JICore
import JIDesign

// W-PLANNER PL-5: the standalone "Workouts" screen is gone — its list, filters, editor, Import
// and per-row actions are the Planner's ALL WORKOUTS (`PlannerView`), over the same
// `WorkoutLibraryViewModel`. What stays here is shared by the Planner and the Import sheet.

/// W-FIX10 F10-3 (B40 obs 2): the Import row's colour — muted while it cannot run (offline, no
/// Garmin), CTA blue when it can. The native tint kept the icon accent green while disabled.
nonisolated func workoutsImportRole(disabled: Bool) -> JIColorRole { disabled ? .muted : .info }

/// The DEBUG launch route `-workout-library-open` names (nil = none / not understood). The Planner
/// opens the editor (new / that row) or the Import sheet once it is up, so a scripted simulator
/// run reaches both without a tap.
nonisolated enum WorkoutLibraryLaunchRoute: Equatable, Sendable {
    case newWorkout, importSheet, edit(Int)
}

nonisolated func workoutLibraryLaunchRoute(_ arguments: [String]) -> WorkoutLibraryLaunchRoute? {
    guard let i = arguments.firstIndex(of: "-workout-library-open"), i + 1 < arguments.count else { return nil }
    let v = arguments[i + 1]
    switch v {
    case "new": return .newWorkout
    case "import": return .importSheet
    default:
        guard v.hasPrefix("t"), let id = Int(v.dropFirst()) else { return nil }
        return .edit(id)
    }
}
