#if canImport(WorkoutKit)
import Foundation
import WorkoutKit

public enum WorkoutSchedulerSenderError: Error, Equatable, Sendable, LocalizedError {
    /// `WorkoutScheduler.isSupported == false` — no paired Apple Watch on this iPhone.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .unsupported: "Workout scheduling needs a paired Apple Watch."
        }
    }
}

/// B-37-L2 (P-workouts) — the real `WorkoutSending` over `WorkoutScheduler.shared`. `schedule` /
/// `remove` on the scheduler never throw, so the only error this sender raises is `.unsupported`
/// (the guard is injectable so the sender is testable without a Watch).
@available(iOS 27, *)
public struct WorkoutSchedulerSender: WorkoutSending {
    private let isSupported: @Sendable () -> Bool

    public init(isSupported: @escaping @Sendable () -> Bool = { WorkoutScheduler.isSupported }) {
        self.isSupported = isSupported
    }

    /// `authorized` → `true`; `notDetermined`/`restricted`/`denied` → `false`.
    public static func granted(_ state: WorkoutScheduler.AuthorizationState) -> Bool {
        state == .authorized
    }

    public func requestAuthorization() async throws -> Bool {
        try ensureSupported()
        return Self.granted(await WorkoutScheduler.shared.requestAuthorization())
    }

    public func schedule(_ plan: WorkoutPlan, at date: DateComponents) async throws {
        try ensureSupported()
        await WorkoutScheduler.shared.schedule(plan, at: date)
    }

    public func remove(_ plan: WorkoutPlan, at date: DateComponents) async throws {
        try ensureSupported()
        await WorkoutScheduler.shared.remove(plan, at: date)
    }

    public func scheduledWorkouts() async throws -> [ScheduledWorkoutPlan] {
        try ensureSupported()
        return await WorkoutScheduler.shared.scheduledWorkouts
    }

    private func ensureSupported() throws {
        guard isSupported() else { throw WorkoutSchedulerSenderError.unsupported }
    }
}
#endif
