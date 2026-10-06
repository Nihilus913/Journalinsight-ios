import Foundation
import UserNotifications
import JIPersistence

// B-43 P2 — the two training nudges the logger was missing:
// • `workoutDay`: "a session is planned today" at 17:30 (off until toggled, Toby 2026-10-04). A
//   repeating calendar trigger cannot ask the plan at fire time, so each planned, not-yet-done day
//   of the cached week gets its own ONE-SHOT dated request (`ji.reminders.workout-day.<date>`),
//   re-laid every time the week summary changes and whenever the toggle/time changes.
// • `sessionOpen`: one-shot 90 min after the last logged set while the session is not ended; every
//   new set pushes it out again, completing the session cancels it (and today's workoutDay).
// State lives in `WorkoutNudgePrefs` (`reminders.workoutNudges`): toggles, time, the last planned
// days seen (so the Reminders toggle can schedule without a hub call) and the day already trained.

public nonisolated struct WorkoutNudgePrefs: Codable, Equatable, Sendable {
    public static let prefKey = "reminders.workoutNudges"
    public static let defaultTime = ReminderTime(hour: 17, minute: 30)

    public var workoutDayEnabled = false
    public var workoutDayTime = Self.defaultTime
    /// Default on: it only ever fires after the user started logging and walked away.
    public var sessionOpenEnabled = true
    /// The cached week's planned, not-yet-done session days: ISO date → session name ("" = unnamed).
    public var planned: [String: String] = [:]
    /// RG-65: the same days' kind (`TrainingWeekDayKind.rawValue`) — only a strength day's nudge
    /// opens the set logger; cardio days (and days whose kind is unknown) open Training.
    public var plannedKinds: [String: String] = [:]
    /// The day a session was completed — its workoutDay reminder is never re-laid.
    public var doneDate: String?

    public init() {}

    private enum CodingKeys: String, CodingKey { case workoutDayEnabled, workoutDayTime, sessionOpenEnabled, planned, plannedKinds, doneDate }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutDayEnabled = try c.decodeIfPresent(Bool.self, forKey: .workoutDayEnabled) ?? false
        workoutDayTime = try c.decodeIfPresent(ReminderTime.self, forKey: .workoutDayTime) ?? Self.defaultTime
        sessionOpenEnabled = try c.decodeIfPresent(Bool.self, forKey: .sessionOpenEnabled) ?? true
        planned = try c.decodeIfPresent([String: String].self, forKey: .planned) ?? [:]
        plannedKinds = try c.decodeIfPresent([String: String].self, forKey: .plannedKinds) ?? [:]
        doneDate = try c.decodeIfPresent(String.self, forKey: .doneDate)
    }

    public static func load(_ prefs: PrefStore?) -> WorkoutNudgePrefs {
        ((try? prefs?.get(prefKey, as: WorkoutNudgePrefs.self)) ?? nil) ?? WorkoutNudgePrefs()
    }

    public func save(_ prefs: PrefStore?) { try? prefs?.set(Self.prefKey, self) }
}

public extension ReminderScheduler {
    nonisolated static let workoutDayTag = ReminderKind.workoutDay.tag
    /// What the logger's deep link is (B-43 P1 owns the route; same string on every training nudge).
    nonisolated static let strengthLogURL = "ji://strength-log"
    /// RG-65: a cardio (interval / long-run) day's nudge opens the Training tab, not the set logger.
    nonisolated static let trainingURL = "ji://training"
    nonisolated static let sessionOpenDelay: TimeInterval = 90 * 60

    nonisolated static func identifier(forWorkoutDay date: String) -> String { "\(ReminderKind.workoutDay.identifier).\(date)" }

    /// The days a workoutDay reminder belongs to: a session day (any non-rest kind) of the week,
    /// today or later, not already trained.
    nonisolated static func plannedWorkoutDays(_ summary: TrainingWeekSummary?, today: String,
                                               doneDate: String? = nil) -> [String: String] {
        var out: [String: String] = [:]
        for day in summary?.days ?? [] where day.kind != .rest && day.done != true && day.date >= today && day.date != doneDate {
            out[day.date] = day.sessionName ?? ""
        }
        return out
    }

    /// RG-65: date → kind raw value for the same days `plannedWorkoutDays` returns.
    nonisolated static func plannedWorkoutKinds(_ summary: TrainingWeekSummary?, today: String,
                                                doneDate: String? = nil) -> [String: String] {
        var out: [String: String] = [:]
        for day in summary?.days ?? [] where day.kind != .rest && day.done != true && day.date >= today && day.date != doneDate {
            out[day.date] = day.kind.rawValue
        }
        return out
    }

    /// RG-65: only a strength day deep-links into the set logger; everything else lands on Training.
    nonisolated static func workoutDayURL(kind: TrainingWeekDayKind?) -> String {
        kind == .strength ? strengthLogURL : trainingURL
    }

    nonisolated static func workoutDayRequest(date: String, sessionName: String?, time: ReminderTime,
                                              kind: TrainingWeekDayKind? = nil) -> UNNotificationRequest? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = ReminderKind.workoutDay.notificationTitle
        let name = sessionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        content.body = name.isEmpty ? ReminderKind.workoutDay.notificationBody : "Today: \(name). Open the logger when you start."
        content.sound = .default
        content.userInfo = [kindKey: workoutDayTag, deepLinkURLKey: workoutDayURL(kind: kind)]
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = time.hour; c.minute = time.minute
        return UNNotificationRequest(identifier: identifier(forWorkoutDay: date), content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
    }

    nonisolated static func sessionOpenRequest(after seconds: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = ReminderKind.sessionOpen.notificationTitle
        content.body = ReminderKind.sessionOpen.notificationBody
        content.sound = .default
        content.userInfo = [kindKey: ReminderKind.sessionOpen.tag, deepLinkURLKey: strengthLogURL]
        return UNNotificationRequest(identifier: ReminderKind.sessionOpen.identifier, content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
    }

    /// Replaces every pending workoutDay request with one per planned day whose fire time is still
    /// ahead of `now`. Returns the dates scheduled.
    @discardableResult
    func scheduleWorkoutDays(_ days: [String: String], at time: ReminderTime, now: Date = Date(),
                             kinds: [String: String] = [:]) async -> [String] {
        await cancelWorkoutDays()
        var scheduled: [String] = []
        for date in days.keys.sorted() {
            guard let request = Self.workoutDayRequest(date: date, sessionName: days[date], time: time,
                                                         kind: kinds[date].flatMap(TrainingWeekDayKind.init(rawValue:))),
                  let fire = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(), fire > now else { continue }
            if (try? await center.add(request)) != nil { scheduled.append(date) }
        }
        return scheduled
    }

    func cancelWorkoutDays() async {
        let ids = await center.pendingRequests()
            .filter { $0.content.userInfo[Self.kindKey] as? String == Self.workoutDayTag }.map(\.identifier)
        if !ids.isEmpty { center.removePendingRequests(withIdentifiers: ids) }
    }

    func cancelWorkoutDay(_ date: String) { center.removePendingRequests(withIdentifiers: [Self.identifier(forWorkoutDay: date)]) }

    /// Pending workoutDay dates (yyyy-MM-dd), sorted.
    func pendingWorkoutDays() async -> [String] {
        let prefix = ReminderKind.workoutDay.identifier + "."
        return await center.pendingRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }.sorted()
    }

    /// (Re)lays the session-left-open nudge 90 min after `lastSetAt`; nothing when that is past.
    func scheduleSessionOpen(lastSetAt: Date, now: Date = Date()) async {
        cancelSessionOpen()
        let remaining = lastSetAt.addingTimeInterval(Self.sessionOpenDelay).timeIntervalSince(now)
        guard remaining > 0 else { return }
        try? await center.add(Self.sessionOpenRequest(after: remaining))
    }

    func cancelSessionOpen() { center.removePendingRequests(withIdentifiers: [ReminderKind.sessionOpen.identifier]) }
}

/// What the phone logger tells the reminders about (nil in previews / tests that don't care).
@MainActor
public protocol WorkoutSessionReminding: AnyObject, Sendable {
    func setLogged(at: Date) async
    func sessionEnded(date: String) async
}

/// The app's `WorkoutSessionReminding` + the week-summary hook: one place that reads the nudge
/// prefs and talks to the scheduler.
@MainActor
public final class WorkoutSessionReminders: WorkoutSessionReminding {
    private let scheduler: ReminderScheduler
    private let prefs: PrefStore?
    private let now: () -> Date
    private let today: () -> String

    public init(scheduler: ReminderScheduler, prefs: PrefStore?, now: @escaping () -> Date = Date.init,
                today: @escaping () -> String = { ReminderScheduler.todayISO() }) {
        self.scheduler = scheduler; self.prefs = prefs; self.now = now; self.today = today
    }

    public func setLogged(at: Date) async {
        guard WorkoutNudgePrefs.load(prefs).sessionOpenEnabled else { scheduler.cancelSessionOpen(); return }
        await scheduler.scheduleSessionOpen(lastSetAt: at, now: now())
    }

    /// Session completed: no open-session nudge, and no "planned today" ping for a day already trained.
    public func sessionEnded(date: String) async {
        scheduler.cancelSessionOpen()
        scheduler.cancelWorkoutDay(date)
        var p = WorkoutNudgePrefs.load(prefs)
        p.doneDate = date
        p.planned[date] = nil
        p.plannedKinds[date] = nil
        p.save(prefs)
    }

    /// Called whenever the cached week changes: remembers its planned days and, when the toggle is
    /// on, re-lays the dated requests.
    public func weekChanged(_ summary: TrainingWeekSummary?) async {
        guard let summary else { return }
        var p = WorkoutNudgePrefs.load(prefs)
        p.planned = ReminderScheduler.plannedWorkoutDays(summary, today: today(), doneDate: p.doneDate)
        p.plannedKinds = ReminderScheduler.plannedWorkoutKinds(summary, today: today(), doneDate: p.doneDate)
        p.save(prefs)
        guard p.workoutDayEnabled else { return }
        await scheduler.scheduleWorkoutDays(p.planned, at: p.workoutDayTime, now: now(), kinds: p.plannedKinds)
    }
}
