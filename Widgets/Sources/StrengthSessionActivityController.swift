import ActivityKit
import Foundation
import JICore

/// Same documented-safety box as `LiveActivityController.swift` (ActivityKit's `Activity` is safe
/// to drive from any thread but declares no `Sendable`); kept file-private so the two controllers
/// stay independent.
private final class StrengthActivityBox<Value>: @unchecked Sendable {
    nonisolated(unsafe) let value: Value
    init(value: Value) { self.value = value }
}

/// W-B38-B B-7 — owns the one strength-session Live Activity: started when the Watch session's
/// mirror reaches the phone, updated on each set / rest / HR change, ended when the session ends.
/// Member of the app AND the extension targets (like `LiveActivityController`); only the app calls it.
@MainActor
public final class StrengthSessionActivityController {
    public static let shared = StrengthSessionActivityController()

    private nonisolated(unsafe) var activity: Activity<StrengthSessionActivityAttributes>?
    /// The last state pushed — HR ticks only update when the shown text would change.
    private var lastState: StrengthSessionActivityState?

    init() {}

    public var isRunning: Bool { activity != nil }

    /// Starts the activity (or adopts the one a previous launch left on the Lock Screen).
    public func start(startedAt: Date, state: StrengthSessionActivityState) {
        if activity == nil {
            activity = Activity<StrengthSessionActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
        }
        if activity != nil { update(state); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: StrengthSessionActivityAttributes(startedAt: startedAt),
                                            content: ActivityContent(state: state, staleDate: nil))
            lastState = state
        } catch {
            // Live Activities unavailable (disabled, over budget) — the session itself is unaffected.
        }
    }

    public func update(_ state: StrengthSessionActivityState) {
        guard let activity else { return }
        var cmp = state; cmp.updatedAt = lastState?.updatedAt ?? state.updatedAt
        if cmp == lastState { return }
        lastState = state
        let box = StrengthActivityBox(value: activity)
        let content = ActivityContent(state: state, staleDate: nil)
        Task.detached { await box.value.update(content) }
    }

    /// Ends the activity with its final state, dismissed by the system's default policy.
    public func end(final state: StrengthSessionActivityState? = nil) {
        guard let activity else { return }
        let box = StrengthActivityBox(value: activity)
        let content = (state ?? lastState).map { ActivityContent(state: $0, staleDate: nil) }
        Task.detached { await box.value.end(content, dismissalPolicy: .default) }
        self.activity = nil
        lastState = nil
    }
}
