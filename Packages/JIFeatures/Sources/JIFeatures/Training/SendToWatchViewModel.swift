#if canImport(WorkoutKit)
import Foundation
import Observation
import WorkoutKit
import JICore
import JIWorkouts

/// B-37-L3 (P-workouts) — drives the Training "Send to Watch" sheet (spec §3 UI): loads the
/// `plan.workout_template` rows through `WorkoutTemplatesProviding`, keeps a multi-select set and a
/// target date (default today), and `send()` builds one WorkoutKit plan per selected template and
/// schedules it through the `WorkoutSending` seam. Per-workout delivery only — never "send week"
/// (spec §1). The builder is injectable so this lane's tests never wait on L2's real
/// `WorkoutBuilder`; the default is `WorkoutBuilder.build`.
@MainActor @Observable
public final class SendToWatchViewModel {
    public typealias Builder = @Sendable (WorkoutTemplate) throws -> WorkoutPlan

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case sending
        /// `n` plans scheduled on the last `send()`.
        case sent(Int)
        /// `requestAuthorization()` answered `false` — the sheet shows copy + a Settings link.
        case authDenied
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var templates: [WorkoutTemplate] = []
    /// `WorkoutTemplate.templateId`s picked for sending.
    public private(set) var selected: Set<Int> = []
    /// Names scheduled by the last successful `send()`, in template order (the "scheduled" rows).
    public private(set) var sentNames: [String] = []
    /// The day (and time) the plans are scheduled for; default = today.
    public var date: Date

    private let provider: any WorkoutTemplatesProviding
    private let sender: any WorkoutSending
    private let builder: Builder
    private let calendar: Calendar
    /// Auth-denied escape hatch: the app wires `UIApplication.openSettingsURLString` here.
    public let openSettings: () -> Void

    public init(
        provider: any WorkoutTemplatesProviding,
        sender: any WorkoutSending,
        builder: @escaping Builder = WorkoutBuilder.build,
        now: () -> Date = Date.init,
        calendar: Calendar = .current,
        openSettings: @escaping () -> Void = {},
        // B-33 §8.5: `ImageRenderer` runs no `.task`, so the sweep would only ever photograph the
        // pre-load empty state. A seed lets the screenshot entry start from a loaded list; the app
        // never passes it (default `[]`), and `load()` overwrites it on the first real fetch.
        seededTemplates: [WorkoutTemplate] = []
    ) {
        self.provider = provider
        self.sender = sender
        self.builder = builder
        self.calendar = calendar
        self.openSettings = openSettings
        self.date = now()
        self.templates = seededTemplates
    }

    public func load() async {
        state = .loading
        do {
            templates = try await provider.workoutTemplates()
            selected = selected.intersection(templates.map(\.templateId))
            state = .idle
        } catch {
            templates = []
            state = .error(Self.describe(error))
        }
    }

    public func toggle(_ templateId: Int) {
        if selected.contains(templateId) { selected.remove(templateId) } else { selected.insert(templateId) }
    }

    public func isSelected(_ templateId: Int) -> Bool { selected.contains(templateId) }

    public var isBusy: Bool { state == .loading || state == .sending }

    /// The send button's enabled state: something picked and nothing in flight.
    public var canSend: Bool { !selected.isEmpty && !isBusy }

    /// Human copy for the status row under the list (empty when there is nothing to say).
    public var statusMessage: String {
        switch state {
        case .idle, .loading: ""
        case .sending: "Sending to Watch…"
        case .sent(let n): n == 1 ? "1 workout scheduled." : "\(n) workouts scheduled."
        case .authDenied: "Workout scheduling isn't allowed. Enable it for JournalInsight in Settings › Privacy › Workouts."
        case .error(let msg): msg
        }
    }

    /// Builds + schedules one plan per selected template (template order). No-op when nothing is
    /// selected. Any failure — builder (e.g. the 175 cap), authorization, or the scheduler — leaves
    /// the selection untouched so the user can retry.
    public func send() async {
        guard canSend else { return }
        state = .sending
        let picked = templates.filter { selected.contains($0.templateId) }
        let at = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        do {
            guard try await sender.requestAuthorization() else {
                state = .authDenied
                return
            }
            // Build every plan first so a cap violation schedules nothing at all.
            let plans = try picked.map { (name: $0.name, plan: try builder($0)) }
            for entry in plans { try await sender.schedule(entry.plan, at: at) }
            sentNames = plans.map(\.name)
            state = .sent(plans.count)
        } catch {
            state = .error(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HubError.unauthorized: "Hub rejected the token — check Settings › Connection."
        case let e as HubError: "Hub error: \(e)"
        case WorkoutBuilderError.capExceeded(let bpm): "A step targets \(bpm) bpm — above the 175 bpm cap. Fix the template on the hub."
        case WorkoutBuilderError.notImplemented: "Workout builder not available in this build."
        default: "Couldn't send: \(error.localizedDescription)"
        }
    }
}
#endif
