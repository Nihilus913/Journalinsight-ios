#if canImport(WorkoutKit)
import Foundation
import WorkoutKit

/// B-37-L1 — test/`-ui-testing` double for `WorkoutSending`: records every call, and lets a test
/// pick the authorization answer or make any call throw. `actor` so it is `Sendable` without locks.
public actor FakeWorkoutSender: WorkoutSending {
    public enum Call: Sendable, Equatable {
        case requestAuthorization
        case schedule(planId: UUID, at: DateComponents)
        case remove(planId: UUID, at: DateComponents)
        case scheduledWorkouts
    }

    public private(set) var calls: [Call] = []
    /// The plans handed to `schedule` in order (the fake keeps them, so `scheduledWorkouts()`
    /// answers with what was scheduled and `remove` drops them again).
    public private(set) var scheduled: [(plan: WorkoutPlan, at: DateComponents)] = []
    public var authorizationResult: Bool
    public var error: (any Error)?

    public init(authorizationResult: Bool = true, error: (any Error)? = nil) {
        self.authorizationResult = authorizationResult
        self.error = error
    }

    public func setAuthorizationResult(_ granted: Bool) { authorizationResult = granted }
    public func setError(_ error: (any Error)?) { self.error = error }

    public func requestAuthorization() async throws -> Bool {
        calls.append(.requestAuthorization)
        if let error { throw error }
        return authorizationResult
    }

    public func schedule(_ plan: WorkoutPlan, at date: DateComponents) async throws {
        calls.append(.schedule(planId: plan.id, at: date))
        if let error { throw error }
        scheduled.append((plan, date))
    }

    public func remove(_ plan: WorkoutPlan, at date: DateComponents) async throws {
        calls.append(.remove(planId: plan.id, at: date))
        if let error { throw error }
        scheduled.removeAll { $0.plan.id == plan.id && $0.at == date }
    }

    public func scheduledWorkouts() async throws -> [ScheduledWorkoutPlan] {
        calls.append(.scheduledWorkouts)
        if let error { throw error }
        return scheduled.map { ScheduledWorkoutPlan($0.plan, date: $0.at) }
    }
}
#endif
