#if canImport(WorkoutKit)
import Foundation
import JICore
import WorkoutKit

public enum WorkoutBuilderError: Error, Equatable, Sendable {
    /// B-37-L1 STUB — L2 replaces the body with the real `CustomWorkout` build (spec §3).
    case notImplemented
    /// Some step's `hrHi` exceeds the 175 bpm cap (`project_docs_map` AWU zones).
    case capExceeded(bpm: Int)
}

/// B-37 (P-workouts) — `WorkoutTemplate` → WorkoutKit `WorkoutPlan` (absolute-bpm alerts, 175 cap).
public enum WorkoutBuilder {
    public static let hrCap = 175

    public static func build(_ template: WorkoutTemplate) throws -> WorkoutPlan {
        throw WorkoutBuilderError.notImplemented
    }
}
#endif
