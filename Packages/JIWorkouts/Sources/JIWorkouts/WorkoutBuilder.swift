#if canImport(WorkoutKit)
import Foundation
import HealthKit
import JICore
import struct JICore.WorkoutStep  // unqualified `WorkoutStep` = the DTO (`public enum JICore` shadows the module name); the kit step is `WorkoutKit.WorkoutStep`
import WorkoutKit

public enum WorkoutBuilderError: Error, Equatable, Sendable {
    /// Kept from the L1 stub for source compatibility; the builder never throws it since B-37-L2.
    case notImplemented
    /// Some step's `hrHi` is above the user's HR cap (B-57 W4: only when the user set one).
    case capExceeded(bpm: Int)
    /// Some step's `hrHi` reaches the user's Zone 5, which the user chose to avoid.
    case zone5Target(bpm: Int, zone5FloorBpm: Int)
    /// `hrLo` is not below `hrHi`, or a bound is non-positive.
    case invalidRange(lo: Int, hi: Int)
    /// A step's `seconds` is not positive.
    case invalidDuration(seconds: Int)
    /// `template.activity` has no `HKWorkoutActivityType` mapping (cardio only, spec §1).
    case unsupportedActivity(String)
    /// The template has no steps.
    case noSteps
    /// W-B40: a distance end is not positive.
    case invalidDistance(meters: Double)
    /// W-B40: an `hr_zone` target with no (valid) user zones to resolve it — never guessed.
    case unresolvedZone(Int)
    /// W-B40: every segment is strength — nothing WorkoutKit can run (B-38 owns strength).
    case noCardioSegment
}

/// B-37 (P-workouts) — `WorkoutTemplate` → WorkoutKit `WorkoutPlan` (spec §3).
///
/// Mapping (Contract rule): leading `warmup` → `CustomWorkout.warmup`, trailing `cooldown` →
/// `.cooldown`; a `work` step immediately followed by a `recovery` step with the same `repeat`
/// → one `IntervalBlock([work, recovery], iterations: repeat)`; any other step → its own block
/// with `iterations: repeat`. Every targeted step carries an absolute-bpm `HeartRateRangeAlert`
/// (never a zone alert), and the plan is rejected when a step targets above the user's cap or
/// inside the Zone 5 they chose to avoid (`WorkoutHrLimits`; none by default).
///
/// W-B40 L2 (B-40b-1, spec §4): built from the template's cardio `segments` (a pre-053 row's
/// compat `steps` = one running segment). `end` → `.time` / `.distance` / `.open` (lap);
/// `target` → `.heartRate(lo...hi)`, a zone resolved to bpm from the USER's zones (B-57 W4 — no
/// zones = `.unresolvedZone`, never a guessed range), `.none` → no alert. Strength segments —
/// including a cardio warm-up inside one — are skipped and reported (`skippedStrength`), not an
/// error: WorkoutKit has no strength type (B-38 owns strength on the Watch).
public enum WorkoutBuilder {
    /// A built plan plus what was left out of it.
    public struct Result {
        public let plan: WorkoutPlan
        /// The template had strength segment(s) that were not sent (spec §4).
        public let skippedStrength: Bool
    }

    /// No limits: the user set no cap and does not avoid Zone 5 (both optional, Toby 2026-09-24).
    public static func build(_ template: WorkoutTemplate) throws -> WorkoutPlan { try build(template, limits: .none) }

    /// Every step keeps its own absolute-bpm target-range alert from the template. `limits` only
    /// rejects a plan that would target above the user's cap or inside their avoided Zone 5.
    public static func build(_ template: WorkoutTemplate, limits: WorkoutHrLimits) throws -> WorkoutPlan {
        try buildReport(template, limits: limits, zones: nil).plan
    }

    /// `zones` resolves `hr_zone` targets (the user's own zones; nil = none set).
    public static func build(_ template: WorkoutTemplate, limits: WorkoutHrLimits, zones: HrZones?) throws -> WorkoutPlan {
        try buildReport(template, limits: limits, zones: zones).plan
    }

    public static func buildReport(_ template: WorkoutTemplate, limits: WorkoutHrLimits, zones: HrZones?) throws -> Result {
        let segments = template.effectiveSegments
        let cardioSegments = segments.filter { $0.sport.isCardio }
        let skippedStrength = segments.contains { $0.sport == .strength }
        if !template.segments.isEmpty, cardioSegments.isEmpty { throw WorkoutBuilderError.noCardioSegment }
        let activity: HKWorkoutActivityType = template.segments.isEmpty
            ? try activityType(template.activity)
            : try activityType(cardioSegments[0].sport.rawValue)
        let cardio = cardioSegments.flatMap { $0.steps.compactMap(\.cardio) }
        guard !cardio.isEmpty else { throw WorkoutBuilderError.noSteps }
        let resolved = try cardio.map { try resolve($0, limits: limits, zones: zones) }

        var steps = resolved[...]
        var warmup: WorkoutKit.WorkoutStep?
        var cooldown: WorkoutKit.WorkoutStep?
        if let first = steps.first, first.step.purpose == .warmup {
            warmup = kitStep(first)
            steps = steps.dropFirst()
        }
        if let last = steps.last, last.step.purpose == .cooldown {
            cooldown = kitStep(last)
            steps = steps.dropLast()
        }

        var blocks: [IntervalBlock] = []
        var index = steps.startIndex
        while index < steps.endIndex {
            let step = steps[index]
            let next = steps.index(after: index)
            if step.step.purpose == .work, next < steps.endIndex, steps[next].step.purpose == .recovery, steps[next].step.repeat == step.step.repeat {
                blocks.append(IntervalBlock(
                    steps: [IntervalStep(.work, step: kitStep(step)), IntervalStep(.recovery, step: kitStep(steps[next]))],
                    iterations: step.step.repeat))
                index = steps.index(after: next)
            } else {
                blocks.append(IntervalBlock(steps: [IntervalStep(purpose(step.step.purpose), step: kitStep(step))], iterations: step.step.repeat))
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
        return Result(plan: WorkoutPlan(.custom(workout)), skippedStrength: skippedStrength)
    }

    // MARK: - pieces

    /// A cardio step with its target resolved to absolute bpm (nil = no alert).
    struct Resolved {
        let step: CardioStep
        let bpm: ClosedRange<Int>?
    }

    static func resolve(_ step: CardioStep, limits: WorkoutHrLimits, zones: HrZones?) throws -> Resolved {
        switch step.end {
        case .time(let s): guard s > 0 else { throw WorkoutBuilderError.invalidDuration(seconds: s) }
        case .distance(let m): guard m > 0 else { throw WorkoutBuilderError.invalidDistance(meters: m) }
        case .lap: break
        }
        let range: ClosedRange<Int>?
        switch step.target {
        case .none: range = nil
        case .hrRange(let lo, let hi):
            guard lo > 0, lo < hi else { throw WorkoutBuilderError.invalidRange(lo: lo, hi: hi) }
            range = lo...hi
        case .hrZone(let zone): range = try zoneRange(zone, zones: zones)
        }
        if let range {
            if let cap = limits.capBpm, range.upperBound > cap { throw WorkoutBuilderError.capExceeded(bpm: range.upperBound) }
            if let z5 = limits.zone5FloorBpm, range.upperBound >= z5 {
                throw WorkoutBuilderError.zone5Target(bpm: range.upperBound, zone5FloorBpm: z5)
            }
        }
        return Resolved(step: step, bpm: range)
    }

    /// Zone n → [floor n, floor n+1 − 1]; Z5 ends at max HR only when max HR is the anchor (an
    /// LTHR-anchored Z5 is open-ended, so it has no alert range to give).
    static func zoneRange(_ zone: Int, zones: HrZones?) throws -> ClosedRange<Int> {
        guard let zones, zones.isValid, (1...5).contains(zone) else { throw WorkoutBuilderError.unresolvedZone(zone) }
        let lo = zones.floorsBpm[zone - 1]
        if zone < 5 { return lo...(zones.floorsBpm[zone] - 1) }
        guard zones.anchor == .maxHr, zones.anchorBpm > lo else { throw WorkoutBuilderError.unresolvedZone(zone) }
        return lo...zones.anchorBpm
    }

    static func validate(_ step: WorkoutStep, limits: WorkoutHrLimits = .none) throws {
        _ = try resolve(CardioStep(step), limits: limits, zones: nil)
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

    static func purpose(_ purpose: WorkoutStepPurpose) -> IntervalStep.Purpose {
        purpose == .recovery ? .recovery : .work
    }

    static func displayName(_ purpose: WorkoutStepPurpose) -> String {
        switch purpose {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }

    static func kitStep(_ resolved: Resolved) -> WorkoutKit.WorkoutStep {
        WorkoutKit.WorkoutStep(
            goal: goal(resolved.step.end),
            alert: resolved.bpm.map { .heartRate(Double($0.lowerBound)...Double($0.upperBound)) },
            displayName: displayName(resolved.step.purpose))
    }

    static func goal(_ end: StepEnd) -> WorkoutGoal {
        switch end {
        case .time(let s): .time(Double(s), .seconds)
        case .distance(let m): .distance(m, .meters)
        case .lap: .open
        }
    }
}
#endif
