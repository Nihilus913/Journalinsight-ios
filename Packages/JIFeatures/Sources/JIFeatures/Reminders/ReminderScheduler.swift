import Foundation
import UserNotifications

// W5a-L2 (P-reminders) — port of `mobile/src/notify/reminders.ts` (v1.18.2). Behind a protocol
// with a fake centre in tests. RN identifies "our" scheduled notifications by a `content.data.kind`
// tag (expo mints the identifier); `UNUserNotificationCenter` needs an identifier up front, so each
// kind gets a deterministic one AND keeps the RN tag in `userInfo` — cancel/get are correct by
// identifier and by tag alike. The 05:10 floor reuses `App/Notifications/LocalVerdictFloor`'s
// identifier (`ji.notifications.verdict-floor`, the one pending request the app schedules at
// launch) so this screen toggles THAT reminder rather than adding a second floor.

/// Wall-clock hour/minute, device-local (UI-layer scheduling, not `JICompute`).
public nonisolated struct ReminderTime: Codable, Equatable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
}

/// The four daily reminders (`useReminderToggle` instances in `reminders.tsx`), copy verbatim.
public nonisolated enum ReminderKind: String, CaseIterable, Codable, Sendable {
    case journal, mind, dose, gateFloor

    /// RN `content.data.kind`.
    public var tag: String {
        switch self {
        case .journal: "journal-reminder"
        case .mind: "mind-reminder"
        case .dose: "dose-reminder"
        case .gateFloor: "gate-floor"
        }
    }

    public var identifier: String {
        switch self {
        case .gateFloor: ReminderScheduler.verdictFloorIdentifier
        default: "ji.reminders.\(tag)"
        }
    }

    public var notificationTitle: String {
        switch self {
        case .journal: "Time to journal ✍️"
        case .mind: "How are you today? 🧠"
        case .dose: "Log today's dose 💊"
        case .gateFloor: "Readiness floor ⏰"
        }
    }

    public var notificationBody: String {
        switch self {
        case .journal: "Take a minute to reflect on your day."
        case .mind: "A daily check-in takes about 10 seconds."
        case .dose: "One tap in the check-in keeps the consecutive-dosing count accurate."
        case .gateFloor: "05:10 local — check today's readiness verdict."
        }
    }

    /// Screen defaults (`reminders.tsx`: journal 21:00, mind 09:00, dose 08:30, floor 05:10).
    public var defaultTime: ReminderTime {
        switch self {
        case .journal: ReminderTime(hour: 21, minute: 0)
        case .mind: ReminderTime(hour: 9, minute: 0)
        case .dose: ReminderTime(hour: 8, minute: 30)
        case .gateFloor: ReminderTime(hour: 5, minute: 10)
        }
    }

    /// Section header + caption, verbatim `reminders.tsx`.
    public var sectionTitle: String {
        switch self {
        case .journal: "Journal reminder"
        case .mind: "Mind check-in reminder"
        case .dose: "Dose reminder"
        case .gateFloor: "Readiness floor"
        }
    }

    public var sectionCaption: String {
        switch self {
        case .journal: "A daily nudge to take a minute and write."
        case .mind: "A separate daily nudge for the mood/stress/energy check-in — own time, own toggle."
        case .dose: "Optional nudge to log whether you took your dose today — keeps the readiness gate's consecutive-dosing count accurate."
        case .gateFloor: "A 05:10 local nudge that opens straight into today's readiness rationale."
        }
    }
}

/// expo's (and `Calendar`'s Gregorian) weekday numbering: 1 = Sunday … 7 = Saturday.
public nonisolated enum Weekday: Int, CaseIterable, Codable, Sendable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// RN `WEEKDAYS`: Mon..Sun display order.
    public nonisolated static let displayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public var label: String {
        switch self {
        case .sunday: "Sunday"; case .monday: "Monday"; case .tuesday: "Tuesday"; case .wednesday: "Wednesday"
        case .thursday: "Thursday"; case .friday: "Friday"; case .saturday: "Saturday"
        }
    }

    public var shortLabel: String { String(label.prefix(3)) }
}

/// The slice of `UNUserNotificationCenter` the scheduler uses — a fake in tests.
public protocol ReminderNotificationCenter: AnyObject {
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

extension UNUserNotificationCenter: ReminderNotificationCenter {
    public func pendingRequests() async -> [UNNotificationRequest] { await pendingNotificationRequests() }
    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    public func authorizationStatus() async -> UNAuthorizationStatus { await notificationSettings().authorizationStatus }
    public func requestAuthorization() async throws -> Bool { try await requestAuthorization(options: [.alert, .sound, .badge]) }
}

public struct ReminderScheduler {
    /// `LocalVerdictFloor.identifier` (App target — not importable from JIFeatures, so the string
    /// is repeated here; `RemindersSchedulerTests` pins it).
    public nonisolated static let verdictFloorIdentifier = "ji.notifications.verdict-floor"
    public nonisolated static let kindKey = "kind"
    public nonisolated static let weekdayKey = "weekday"
    /// `LocalVerdictFloor.deepLinkURLKey` — what `NtfyDeepLink` reads back on tap.
    public nonisolated static let deepLinkURLKey = "url"
    public nonisolated static let workoutTag = "workout-reminder"
    public nonisolated static let workoutTitle = "Workout time 🏋️"
    public nonisolated static let workoutBody = "Today's the day — get your session in."

    private let center: any ReminderNotificationCenter

    public init(center: any ReminderNotificationCenter) { self.center = center }

    // MARK: pure

    /// "HH:MM" 24h, zero-padded.
    public nonisolated static func formatTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    public nonisolated static func isValidTime(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    /// Wraps a minute-of-day offset into [0, 1440) — 23:50 + 15 min → 00:05.
    public nonisolated static func wrapMinutesOfDay(_ total: Int) -> Int {
        let span = 24 * 60
        return ((total % span) + span) % span
    }

    /// RN `gateFloorReminderData(date)`: `ji://gate?date=<YYYY-MM-DD>`, "today" recomputed on every
    /// (re)schedule because a queued payload can't compute it later.
    public nonisolated static func gateFloorURL(today: String) -> String { "ji://gate?date=\(today)" }

    public nonisolated static func identifier(forWorkout weekday: Weekday) -> String {
        "ji.reminders.\(workoutTag).\(weekday.rawValue)"
    }

    public nonisolated static func request(kind: ReminderKind, time: ReminderTime, today: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind.notificationTitle
        content.body = kind.notificationBody
        content.sound = .default
        var userInfo: [String: Any] = [kindKey: kind.tag]
        if kind == .gateFloor { userInfo[deepLinkURLKey] = gateFloorURL(today: today) }
        content.userInfo = userInfo
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: kind.identifier, content: content, trigger: trigger)
    }

    public nonisolated static func workoutRequest(weekday: Weekday, time: ReminderTime) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = workoutTitle
        content.body = workoutBody
        content.sound = .default
        content.userInfo = [kindKey: workoutTag, weekdayKey: weekday.rawValue]
        var components = DateComponents()
        components.weekday = weekday.rawValue
        components.hour = time.hour
        components.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: identifier(forWorkout: weekday), content: content, trigger: trigger)
    }

    private nonisolated static func time(of request: UNNotificationRequest) -> ReminderTime? {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let hour = trigger.dateComponents.hour, let minute = trigger.dateComponents.minute else { return nil }
        return ReminderTime(hour: hour, minute: minute)
    }

    private nonisolated static func isOurs(_ request: UNNotificationRequest, tag: String) -> Bool {
        request.content.userInfo[kindKey] as? String == tag
    }

    // MARK: daily

    /// Cancel-then-add under the kind's identifier (RN `scheduleDailyReminderByKind`).
    public func schedule(_ kind: ReminderKind, at time: ReminderTime, today: String = Self.todayISO()) async throws {
        cancel(kind)
        try await center.add(Self.request(kind: kind, time: time, today: today))
    }

    public func cancel(_ kind: ReminderKind) {
        center.removePendingRequests(withIdentifiers: [kind.identifier])
    }

    /// The on/off + time source of truth: the pending request itself (RN `getReminderByKind`).
    public func scheduledTime(for kind: ReminderKind) async -> ReminderTime? {
        for request in await center.pendingRequests()
        where request.identifier == kind.identifier || Self.isOurs(request, tag: kind.tag) {
            if let t = Self.time(of: request) { return t }
        }
        return nil
    }

    // MARK: workouts (per weekday)

    public func scheduleWorkout(_ weekday: Weekday, at time: ReminderTime) async throws {
        cancelWorkout(weekday)
        try await center.add(Self.workoutRequest(weekday: weekday, time: time))
    }

    public func cancelWorkout(_ weekday: Weekday) {
        center.removePendingRequests(withIdentifiers: [Self.identifier(forWorkout: weekday)])
    }

    /// RN `getAllWorkoutReminders`: one scan, absent weekday = off.
    public func allWorkouts() async -> [Weekday: ReminderTime] {
        var out: [Weekday: ReminderTime] = [:]
        for request in await center.pendingRequests() where Self.isOurs(request, tag: Self.workoutTag) {
            guard let raw = request.content.userInfo[Self.weekdayKey] as? Int, let weekday = Weekday(rawValue: raw),
                  let t = Self.time(of: request) else { continue }
            out[weekday] = t
        }
        return out
    }

    // MARK: permission

    /// RN `requestPermission`: true if already granted, else prompts; false (never throws) on
    /// denial or failure.
    public func requestPermission() async -> Bool {
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: break
        }
        do { return try await center.requestAuthorization() } catch { return false }
    }

    public func isDenied() async -> Bool { await center.authorizationStatus() == .denied }

    /// Device-local YYYY-MM-DD (RN `todayISO()`; UI-layer wall clock, deliberately not JICompute).
    public nonisolated static func todayISO(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }
}
