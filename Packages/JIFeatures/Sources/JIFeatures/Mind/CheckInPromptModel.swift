import Foundation
import Observation
import JICore
import JIPersistence

// W-B102 C-3 (BP-23a): evaluates `CheckInTrigger` over the inputs the app gathers, schedules the
// one-shot notification at most once a day, cancels it when no rule holds, and backs the Today
// card's "Not today" and the Settings toggle. State lives in `PrefStore` (on this phone only).

@Observable
@MainActor
public final class CheckInPromptModel {
    public static let enabledKey = "checkin.enabled"
    public static let lastPromptKey = "checkin.lastPromptDay"
    public static let snoozedKey = "checkin.snoozedDay"

    public private(set) var evaluation: CheckInEvaluation = .quiet
    public var livePrompt: CheckInPrompt? { evaluation.prompt }
    /// Bumped on every toggle so views re-read `enabled`.
    public private(set) var revision = 0

    private let center: any ReminderNotificationCenter
    private let prefs: PrefStore

    public init(center: any ReminderNotificationCenter, prefs: PrefStore) {
        self.center = center
        self.prefs = prefs
    }

    /// Default on (Toby asked for the check-in; one toggle silences it).
    public var enabled: Bool {
        _ = revision
        return ((try? prefs.get(Self.enabledKey, as: Bool.self)) ?? nil) ?? true
    }

    public func setEnabled(_ on: Bool) {
        try? prefs.set(Self.enabledKey, on)
        revision += 1
        if !on {
            center.removePendingRequests(withIdentifiers: [CheckInNotification.identifier])
            evaluation = .off
        }
    }

    private func day(_ key: String) -> DayKey? {
        ((try? prefs.get(key, as: String.self)) ?? nil).flatMap { DayKey(iso: $0) }
    }

    /// `inputs.enabled` / `inputs.snoozedDay` are overridden by this phone's prefs.
    /// `now` = device-local hour/minute (the notification fires on the wall clock).
    public func refresh(_ inputs: CheckInInputs, now: DateComponents) async {
        var inputs = inputs
        inputs.enabled = enabled
        inputs.snoozedDay = day(Self.snoozedKey)
        let result = CheckInTrigger.evaluate(inputs)
        evaluation = result
        guard let prompt = result.prompt else {
            center.removePendingRequests(withIdentifiers: [CheckInNotification.identifier])
            return
        }
        // At most one notification a day: once today's is scheduled, never re-add it.
        guard day(Self.lastPromptKey) != inputs.today, let time = CheckInNotification.fireTime(now: now) else { return }
        do {
            try await center.add(CheckInNotification.request(prompt: prompt, at: time))
            try? prefs.set(Self.lastPromptKey, inputs.today.iso)
        } catch {
            // Notifications unavailable: the Today card still asks.
        }
    }

    /// "Not today": hide the card and drop the pending notification until tomorrow.
    public func snoozeToday(_ today: DayKey) {
        try? prefs.set(Self.snoozedKey, today.iso)
        center.removePendingRequests(withIdentifiers: [CheckInNotification.identifier])
        if evaluation.prompt != nil { evaluation = .quiet }
    }

    /// The check-in was saved: the card goes away (the next refresh is quiet because the mind
    /// check-in for today exists).
    public func markAnswered() {
        center.removePendingRequests(withIdentifiers: [CheckInNotification.identifier])
        if evaluation.prompt != nil { evaluation = .quiet }
    }

    /// The last `CheckInTrigger.windowDays` mornings from the hub (`GET /planning/morning-verdict`),
    /// fetched concurrently; a day that throws (404 = no verdict) is absent, never a zero.
    public nonisolated static func loadMornings(today: DayKey,
                                                fetch: @escaping @Sendable (String) async throws -> String?) async -> [CheckInMorning] {
        await withTaskGroup(of: CheckInMorning?.self) { group in
            for i in 0..<CheckInTrigger.windowDays {
                let day = today.adding(days: -i)
                group.addTask {
                    guard let v = try? await fetch(day.iso), !v.isEmpty else { return nil }
                    return CheckInMorning(day: day, verdict: v)
                }
            }
            var out: [CheckInMorning] = []
            for await m in group { if let m { out.append(m) } }
            return out.sorted { $0.day < $1.day }
        }
    }
}
