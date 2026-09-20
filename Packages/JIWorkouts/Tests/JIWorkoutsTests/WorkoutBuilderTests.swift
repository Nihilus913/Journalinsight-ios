import Foundation
import HealthKit
import JICore
import struct JICore.WorkoutStep
import Testing
import WorkoutKit
@testable import JIWorkouts

/// B-37-L2 (P-workouts) — `WorkoutBuilder` per seed template: step counts, alert ranges,
/// iterations, the 175 cap in every alert, and the cap violation path.
struct WorkoutBuilderTests {
    // MARK: helpers

    private func seed() async throws -> [WorkoutTemplate] {
        try await MockDataProvider().workoutTemplates()
    }

    private func seed(_ name: String) async throws -> WorkoutTemplate {
        let all = try await seed()
        return try #require(all.first { $0.name == name }, "seed template \(name)")
    }

    private func custom(_ plan: WorkoutPlan) throws -> CustomWorkout {
        guard case .custom(let workout) = plan.workout else {
            throw TestFailure("plan is not a CustomWorkout")
        }
        return workout
    }

    private func bpm(_ alert: (any WorkoutAlert)?) throws -> ClosedRange<Int> {
        let hr = try #require(alert as? HeartRateRangeAlert, "alert is a HeartRateRangeAlert")
        let lo = hr.target.lowerBound.converted(to: WorkoutAlertMetric.countPerMinute).value
        let hi = hr.target.upperBound.converted(to: WorkoutAlertMetric.countPerMinute).value
        return Int(lo.rounded())...Int(hi.rounded())
    }

    private func seconds(_ goal: WorkoutGoal) throws -> Int {
        guard case .time(let value, let unit) = goal else { throw TestFailure("goal is not .time") }
        return Int(Measurement(value: value, unit: unit).converted(to: .seconds).value.rounded())
    }

    private func template(name: String = "T", location: WorkoutLocation = .outdoor, activity: String = "running", steps: [WorkoutStep]) -> WorkoutTemplate {
        WorkoutTemplate(templateId: 99, name: name, activity: activity, location: location, weekdays: [], steps: steps, updatedAt: "2026-09-21T00:00:00Z")
    }

    struct TestFailure: Error { let message: String; init(_ m: String) { message = m } }

    // MARK: per seed template

    @Test func zone2_40min_isSingleWorkStep() async throws {
        let plan = try WorkoutBuilder.build(try await seed("Zone 2 40 min"))
        let w = try custom(plan)
        #expect(w.activity == .running)
        #expect(w.location == .outdoor)
        #expect(w.displayName == "Zone 2 40 min")
        #expect(try seconds(try #require(w.warmup).goal) == 300)
        #expect(try bpm(w.warmup?.alert) == 100...140)
        #expect(w.blocks.count == 1)
        #expect(w.blocks[0].iterations == 1)
        #expect(w.blocks[0].steps.count == 1)
        #expect(w.blocks[0].steps[0].purpose == .work)
        #expect(try seconds(w.blocks[0].steps[0].step.goal) == 1800)
        #expect(try bpm(w.blocks[0].steps[0].step.alert) == 117...138)
        #expect(try seconds(try #require(w.cooldown).goal) == 300)
        #expect(try bpm(w.cooldown?.alert) == 100...140)
    }

    @Test func norwegian4x4_isOneIntervalBlockOfFour() async throws {
        let plan = try WorkoutBuilder.build(try await seed("Norwegian 4×4"))
        let w = try custom(plan)
        #expect(w.displayName == "Norwegian 4×4")
        #expect(try seconds(try #require(w.warmup).goal) == 600)
        #expect(w.blocks.count == 1)
        let block = w.blocks[0]
        #expect(block.iterations == 4)
        #expect(block.steps.count == 2)
        #expect(block.steps[0].purpose == .work)
        #expect(try seconds(block.steps[0].step.goal) == 240)
        #expect(try bpm(block.steps[0].step.alert) == 160...175)
        #expect(block.steps[1].purpose == .recovery)
        #expect(try seconds(block.steps[1].step.goal) == 180)
        #expect(try bpm(block.steps[1].step.alert) == 100...140)
        #expect(try seconds(try #require(w.cooldown).goal) == 300)
    }

    @Test func zone2_60min_isSingleWorkStep() async throws {
        let w = try custom(try WorkoutBuilder.build(try await seed("Zone 2 60 min")))
        #expect(w.blocks.count == 1 && w.blocks[0].steps.count == 1 && w.blocks[0].iterations == 1)
        #expect(try seconds(w.blocks[0].steps[0].step.goal) == 3000)
        #expect(try bpm(w.blocks[0].steps[0].step.alert) == 117...138)
        #expect(try seconds(try #require(w.warmup).goal) == 300)
        #expect(try seconds(try #require(w.cooldown).goal) == 300)
    }

    @Test func longRun_matchesGarminGolden() async throws {
        // create_running_workout.py golden: 10/75/5 min, 100–140 / 116–138 / 100–140.
        let w = try custom(try WorkoutBuilder.build(try await seed("Long Run Zone 2")))
        #expect(try seconds(try #require(w.warmup).goal) == 600)
        #expect(try bpm(w.warmup?.alert) == 100...140)
        #expect(w.blocks.count == 1 && w.blocks[0].steps.count == 1)
        #expect(try seconds(w.blocks[0].steps[0].step.goal) == 4500)
        #expect(try bpm(w.blocks[0].steps[0].step.alert) == 116...138)
        #expect(try seconds(try #require(w.cooldown).goal) == 300)
        #expect(try bpm(w.cooldown?.alert) == 100...140)
    }

    // MARK: cross-template invariants

    @Test func everySeedPlanCarriesTheCapInEveryAlert() async throws {
        let all = try await seed()
        #expect(all.count == 4)
        for t in all {
            let w = try custom(try WorkoutBuilder.build(t))
            var alerts: [(any WorkoutAlert)?] = [w.warmup?.alert, w.cooldown?.alert]
            alerts += w.blocks.flatMap { $0.steps.map { $0.step.alert } }
            #expect(!alerts.isEmpty)
            for alert in alerts {
                let range = try bpm(alert)
                #expect(range.upperBound <= WorkoutBuilder.hrCap, "\(t.name): \(range) exceeds cap")
                #expect(range.lowerBound < range.upperBound)
            }
        }
    }

    @Test func everySeedPlanIsAbsoluteBpmNeverZone() async throws {
        for t in try await seed() {
            let w = try custom(try WorkoutBuilder.build(t))
            let alerts = [w.warmup?.alert, w.cooldown?.alert] + w.blocks.flatMap { $0.steps.map { $0.step.alert } }
            for alert in alerts { #expect(alert is HeartRateRangeAlert) }
        }
    }

    @Test func stepDisplayNamesFollowPurpose() async throws {
        let w = try custom(try WorkoutBuilder.build(try await seed("Norwegian 4×4")))
        #expect(w.warmup?.displayName == "Warm-up")
        #expect(w.blocks[0].steps[0].step.displayName == "Work")
        #expect(w.blocks[0].steps[1].step.displayName == "Recovery")
        #expect(w.cooldown?.displayName == "Cool-down")
    }

    // MARK: error paths

    @Test func workAbove175Throws() async throws {
        let t = template(steps: [
            WorkoutStep(purpose: .warmup, seconds: 300, hrLo: 100, hrHi: 140),
            WorkoutStep(purpose: .work, seconds: 240, hrLo: 165, hrHi: 180, repeat: 4),
            WorkoutStep(purpose: .recovery, seconds: 180, hrLo: 100, hrHi: 140, repeat: 4),
            WorkoutStep(purpose: .cooldown, seconds: 300, hrLo: 100, hrHi: 140),
        ])
        #expect(throws: WorkoutBuilderError.capExceeded(bpm: 180)) { try WorkoutBuilder.build(t) }
    }

    @Test func exactly175DoesNotThrow() async throws {
        let t = template(steps: [WorkoutStep(purpose: .work, seconds: 60, hrLo: 160, hrHi: 175)])
        #expect(throws: Never.self) { try WorkoutBuilder.build(t) }
    }

    @Test func invertedRangeThrows() async throws {
        let t = template(steps: [WorkoutStep(purpose: .work, seconds: 60, hrLo: 150, hrHi: 120)])
        #expect(throws: WorkoutBuilderError.invalidRange(lo: 150, hi: 120)) { try WorkoutBuilder.build(t) }
    }

    @Test func nonPositiveSecondsThrows() async throws {
        let t = template(steps: [WorkoutStep(purpose: .work, seconds: 0, hrLo: 110, hrHi: 140)])
        #expect(throws: WorkoutBuilderError.invalidDuration(seconds: 0)) { try WorkoutBuilder.build(t) }
    }

    @Test func unknownActivityThrows() async throws {
        let t = template(activity: "rowing", steps: [WorkoutStep(purpose: .work, seconds: 60, hrLo: 110, hrHi: 140)])
        #expect(throws: WorkoutBuilderError.unsupportedActivity("rowing")) { try WorkoutBuilder.build(t) }
    }

    @Test func emptyStepsThrows() async throws {
        #expect(throws: WorkoutBuilderError.noSteps) { try WorkoutBuilder.build(template(steps: [])) }
    }

    // MARK: structure rules

    @Test func indoorLocationMapsToIndoor() async throws {
        let t = template(location: .indoor, steps: [WorkoutStep(purpose: .work, seconds: 60, hrLo: 110, hrHi: 140)])
        #expect(try custom(try WorkoutBuilder.build(t)).location == .indoor)
    }

    @Test func workWithoutMatchingRecoveryRepeatsAlone() async throws {
        // work ×3 followed by recovery ×1: not one pair block (repeat differs) — two blocks.
        let t = template(steps: [
            WorkoutStep(purpose: .work, seconds: 120, hrLo: 150, hrHi: 170, repeat: 3),
            WorkoutStep(purpose: .recovery, seconds: 60, hrLo: 100, hrHi: 140, repeat: 1),
        ])
        let w = try custom(try WorkoutBuilder.build(t))
        #expect(w.blocks.count == 2)
        #expect(w.blocks[0].iterations == 3 && w.blocks[0].steps.count == 1 && w.blocks[0].steps[0].purpose == .work)
        #expect(w.blocks[1].iterations == 1 && w.blocks[1].steps.count == 1 && w.blocks[1].steps[0].purpose == .recovery)
        #expect(w.warmup == nil && w.cooldown == nil)
    }

    @Test func twoIntervalSetsBecomeTwoBlocks() async throws {
        let t = template(steps: [
            WorkoutStep(purpose: .warmup, seconds: 300, hrLo: 100, hrHi: 140),
            WorkoutStep(purpose: .work, seconds: 240, hrLo: 160, hrHi: 175, repeat: 4),
            WorkoutStep(purpose: .recovery, seconds: 180, hrLo: 100, hrHi: 140, repeat: 4),
            WorkoutStep(purpose: .work, seconds: 60, hrLo: 150, hrHi: 170, repeat: 2),
            WorkoutStep(purpose: .recovery, seconds: 60, hrLo: 100, hrHi: 140, repeat: 2),
            WorkoutStep(purpose: .cooldown, seconds: 300, hrLo: 100, hrHi: 140),
        ])
        let w = try custom(try WorkoutBuilder.build(t))
        #expect(w.blocks.count == 2)
        #expect(w.blocks[0].iterations == 4 && w.blocks[1].iterations == 2)
        #expect(w.blocks.allSatisfy { $0.steps.count == 2 })
    }

    @Test func builtPlansAreSchedulableByTheFake() async throws {
        let sender = FakeWorkoutSender()
        let date = DateComponents(year: 2026, month: 9, day: 22)
        for t in try await seed() { try await sender.schedule(try WorkoutBuilder.build(t), at: date) }
        #expect(try await sender.scheduledWorkouts().count == 4)
    }
}
