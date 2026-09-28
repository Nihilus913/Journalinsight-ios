import Foundation
import HealthKit
import JICore
import Testing
import WorkoutKit
@testable import JIWorkouts

/// W-B40 L2 (B-40b-1, spec §4) — the builder over `segments`: three ends (time / distance / lap),
/// three targets (none / hr_range / hr_zone → the USER's zones), strength segments skipped and
/// reported (never an error), the user's cap applied to resolved zone bpm too.
struct WorkoutBuilderSegmentsTests {
    private let zones = HrZones(anchor: .maxHr, anchorBpm: 190, floorsBpm: [100, 116, 139, 160, 176])

    private func template(_ segments: [WorkoutSegment], activity: String = "running") -> WorkoutTemplate {
        WorkoutTemplate(templateId: 7, name: "Seg", activity: activity, location: .outdoor, weekdays: [], steps: [],
                        updatedAt: "2026-09-28T00:00:00Z", segments: segments)
    }

    private func run(_ steps: [CardioStep]) -> WorkoutSegment { WorkoutSegment(sport: .running, steps: steps.map { .cardio($0) }) }

    private func custom(_ plan: WorkoutPlan) throws -> CustomWorkout {
        guard case .custom(let w) = plan.workout else { throw Failure() }
        return w
    }
    struct Failure: Error {}

    private func bpm(_ alert: (any WorkoutAlert)?) throws -> ClosedRange<Int> {
        let hr = try #require(alert as? HeartRateRangeAlert)
        let lo = hr.target.lowerBound.converted(to: WorkoutAlertMetric.countPerMinute).value
        let hi = hr.target.upperBound.converted(to: WorkoutAlertMetric.countPerMinute).value
        return Int(lo.rounded())...Int(hi.rounded())
    }

    @Test func threeEndsMapToTimeDistanceAndOpenGoals() throws {
        let t = template([run([
            CardioStep(purpose: .warmup, end: .lap, target: .none),
            CardioStep(purpose: .work, end: .distance(meters: 800), target: .hrRange(lo: 150, hi: 170)),
            CardioStep(purpose: .work, end: .time(seconds: 600), target: .hrRange(lo: 120, hi: 140)),
        ])])
        let w = try custom(try WorkoutBuilder.build(t))
        #expect(w.warmup?.goal == .open)
        #expect(w.blocks.count == 2)
        #expect(w.blocks[0].steps[0].step.goal == .distance(800, .meters))
        #expect(w.blocks[1].steps[0].step.goal == .time(600, .seconds))
    }

    @Test func targetNoneHasNoAlertAndRangeIsAbsoluteBpm() throws {
        let t = template([run([
            CardioStep(purpose: .work, end: .time(seconds: 60), target: .none),
            CardioStep(purpose: .work, end: .time(seconds: 60), target: .hrRange(lo: 120, hi: 140)),
        ])])
        let w = try custom(try WorkoutBuilder.build(t))
        #expect(w.blocks[0].steps[0].step.alert == nil)
        #expect(try bpm(w.blocks[1].steps[0].step.alert) == 120...140)
    }

    @Test func zoneTargetResolvesFromTheUsersZones() throws {
        let t = template([run([
            CardioStep(purpose: .work, end: .time(seconds: 1800), target: .hrZone(2)),
            CardioStep(purpose: .work, end: .time(seconds: 240), target: .hrZone(4)),
        ])])
        let w = try custom(try WorkoutBuilder.build(t, limits: .none, zones: zones))
        #expect(try bpm(w.blocks[0].steps[0].step.alert) == 116...138)
        #expect(try bpm(w.blocks[1].steps[0].step.alert) == 160...175)
    }

    @Test func zoneTargetWithoutZonesIsNamedNeverGuessed() {
        let t = template([run([CardioStep(purpose: .work, end: .time(seconds: 60), target: .hrZone(2))])])
        #expect(throws: WorkoutBuilderError.unresolvedZone(2)) { try WorkoutBuilder.build(t) }
    }

    @Test func capAppliesToAResolvedZone() {
        let t = template([run([CardioStep(purpose: .work, end: .time(seconds: 60), target: .hrZone(5))])])
        #expect(throws: WorkoutBuilderError.capExceeded(bpm: 190)) {
            try WorkoutBuilder.build(t, limits: WorkoutHrLimits(capBpm: 175), zones: zones)
        }
    }

    @Test func strengthSegmentIsSkippedAndReportedNotAnError() throws {
        let strength = WorkoutSegment(sport: .strength, steps: [
            .cardio(CardioStep(purpose: .warmup, end: .time(seconds: 300), target: .none, description: "Rope")),
            .strength(StrengthStep(exerciseKey: "Barbell Bench Press", garminCategory: "BENCH_PRESS", sets: 3, reps: 12, weightKg: 40)),
        ])
        let t = template([strength, run([CardioStep(purpose: .work, end: .time(seconds: 3600), target: .hrRange(lo: 116, hi: 138))])])
        let result = try WorkoutBuilder.buildReport(t, limits: .none, zones: nil)
        #expect(result.skippedStrength)
        let w = try custom(result.plan)
        #expect(w.warmup == nil, "the strength segment's rope warm-up is not sent to the Watch")
        #expect(w.blocks.count == 1)
        #expect(w.activity == .running)
    }

    @Test func strengthOnlyTemplateHasNoCardioToSend() {
        let t = template([WorkoutSegment(sport: .strength, steps: [.strength(StrengthStep(exerciseKey: "Plank", garminCategory: "PLANK", sets: 3, seconds: 45))])])
        #expect(throws: WorkoutBuilderError.noCardioSegment) { try WorkoutBuilder.build(t) }
    }

    @Test func cardioOnlyReportsNoSkip() throws {
        let t = template([run([CardioStep(purpose: .work, end: .time(seconds: 60), target: .none)])])
        #expect(try WorkoutBuilder.buildReport(t, limits: .none, zones: nil).skippedStrength == false)
    }

    @Test func segmentSportDrivesTheActivity() throws {
        let t = template([WorkoutSegment(sport: .cycling, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 60), target: .none))])])
        #expect(try custom(try WorkoutBuilder.build(t)).activity == .cycling)
    }

    @Test func invalidEndsAreRejected() {
        #expect(throws: WorkoutBuilderError.invalidDuration(seconds: 0)) {
            try WorkoutBuilder.build(template([run([CardioStep(purpose: .work, end: .time(seconds: 0), target: .none)])]))
        }
        #expect(throws: WorkoutBuilderError.invalidDistance(meters: 0)) {
            try WorkoutBuilder.build(template([run([CardioStep(purpose: .work, end: .distance(meters: 0), target: .none)])]))
        }
    }

    @Test func intervalPairStillBecomesOneBlock() throws {
        let t = template([run([
            CardioStep(purpose: .work, end: .time(seconds: 240), target: .hrRange(lo: 160, hi: 175), repeat: 4),
            CardioStep(purpose: .recovery, end: .time(seconds: 180), target: .hrRange(lo: 100, hi: 140), repeat: 4),
        ])])
        let w = try custom(try WorkoutBuilder.build(t))
        #expect(w.blocks.count == 1 && w.blocks[0].iterations == 4 && w.blocks[0].steps.count == 2)
    }
}
