#if canImport(WorkoutKit)
import Foundation
import HealthKit
import JICore
import struct JICore.WorkoutStep  // unqualified `WorkoutStep` = the DTO (`public enum JICore` shadows the module name); the kit step is `WorkoutKit.WorkoutStep`
import WorkoutKit

public enum WorkoutBuilderError: Error, Equatable, Sendable {
    /// Kept from the L1 stub for source compatibility; the builder never throws it since B-37-L2.
    case notImplemented
    /// Some step's `hrHi` exceeds the 175 bpm cap (`project_docs_map` AWU zones).
    case capExceeded(bpm: Int)
    /// `hrLo` is not below `hrHi`, or a bound is non-positive.
    case invalidRange(lo: Int, hi: Int)
    /// A step's `seconds` is not positive.
    case invalidDuration(seconds: Int)
    /// `template.activity` has no `HKWorkoutActivityType` mapping (cardio only, spec §1).
    case unsupportedActivity(String)
    /// The template has no steps.
    case noSteps
}

/// B-37 (P-workouts) — `WorkoutTemplate` → WorkoutKit `WorkoutPlan` (spec §3).
///
/// Mapping (Contract rule): leading `warmup` → `CustomWorkout.warmup`, trailing `cooldown` →
/// `.cooldown`; a `work` step immediately followed by a `recovery` step with the same `repeat`
/// → one `IntervalBlock([work, recovery], iterations: repeat)`; any other step → its own block
/// with `iterations: repeat`. Every step carries an absolute-bpm `HeartRateRangeAlert` (never a
/// zone alert), and the whole plan is rejected when any `hrHi` exceeds `hrCap`.
public enum WorkoutBuilder {
    public static let hrCap = 175

    public static func build(_ template: WorkoutTemplate) throws -> WorkoutPlan {
        guard !template.steps.isEmpty else { throw WorkoutBuilderError.noSteps }
        let activity = try activityType(template.activity)
        for step in template.steps { try validate(step) }

        var steps = template.steps[...]
        var warmup: WorkoutKit.WorkoutStep?
        var cooldown: WorkoutKit.WorkoutStep?
        if let first = steps.first, first.purpose == .warmup {
            warmup = kitStep(first)
            steps = steps.dropFirst()
        }
        if let last = steps.last, last.purpose == .cooldown {
            cooldown = kitStep(last)
            steps = steps.dropLast()
        }

        var blocks: [IntervalBlock] = []
        var index = steps.startIndex
        while index < steps.endIndex {
            let step = steps[index]
            let next = steps.index(after: index)
            if step.purpose == .work, next < steps.endIndex, steps[next].purpose == .recovery, steps[next].repeat == step.repeat {
                blocks.append(IntervalBlock(
                    steps: [IntervalStep(.work, step: kitStep(step)), IntervalStep(.recovery, step: kitStep(steps[next]))],
                    iterations: step.repeat))
                index = steps.index(after: next)
            } else {
                blocks.append(IntervalBlock(steps: [IntervalStep(purpose(step), step: kitStep(step))], iterations: step.repeat))
                index = next
            }
        }

        let workout = CustomWorkout(
            activity: activity,
            location: location(template.location),
            displayName: template.name,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown)
        return WorkoutPlan(.custom(workout))
    }

    // MARK: - pieces

    static func validate(_ step: WorkoutStep) throws {
        guard step.seconds > 0 else { throw WorkoutBuilderError.invalidDuration(seconds: step.seconds) }
        guard step.hrLo > 0, step.hrLo < step.hrHi else { throw WorkoutBuilderError.invalidRange(lo: step.hrLo, hi: step.hrHi) }
        guard step.hrHi <= hrCap else { throw WorkoutBuilderError.capExceeded(bpm: step.hrHi) }
    }

    static func activityType(_ activity: String) throws -> HKWorkoutActivityType {
        switch activity.lowercased() {
        case "running": .running
        case "walking": .walking
        case "cycling": .cycling
        default: throw WorkoutBuilderError.unsupportedActivity(activity)
        }
    }

    static func location(_ location: WorkoutLocation) -> HKWorkoutSessionLocationType {
        switch location {
        case .outdoor: .outdoor
        case .indoor: .indoor
        }
    }

    static func purpose(_ step: WorkoutStep) -> IntervalStep.Purpose {
        step.purpose == .recovery ? .recovery : .work
    }

    static func displayName(_ purpose: WorkoutStepPurpose) -> String {
        switch purpose {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }

    static func kitStep(_ step: WorkoutStep) -> WorkoutKit.WorkoutStep {
        WorkoutKit.WorkoutStep(
            goal: .time(Double(step.seconds), .seconds),
            alert: .heartRate(Double(step.hrLo)...Double(step.hrHi)),
            displayName: displayName(step.purpose))
    }
}
#endif
