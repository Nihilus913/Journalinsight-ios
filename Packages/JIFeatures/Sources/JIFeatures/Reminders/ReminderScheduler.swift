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

/// The four daily reminders (`useReminderToggle` instances in `reminders.tsx`), copy verbatim,
/// plus the B-57 W4 one-shot `hrCapCheck` (8-week re-check of the user's own HR cap).
public nonisolated enum ReminderKind: String, CaseIterable, Codable, Sendable {
    case journal, mind, dose, gateFloor, hrCapCheck
    /// B-43 P2: "a session is planned today" (dated one-shots per planned day) and "your session is
    /// still open" (one-shot 90 min after the last set) — `WorkoutSessionReminders.swift`.
    case workoutDay, sessionOpen

    /// The four repeating daily reminders. `hrCapCheck` is a one-shot dated reminder (8-week
    /// re-check) and is scheduled only through `scheduleHrCapCheck`.
    public static let dailyCases: [ReminderKind] = [.journal, .mind, .dose, .gateFloor]

    /// RN `content.data.kind`.
    public var tag: String {
        switch self {
        case .journal: "journal-reminder"
        case .mind: "mind-reminder"
        case .dose: "dose-reminder"
        case .gateFloor: "gate-floor"
        case .hrCapCheck: "hr-cap-check"
        case .workoutDay: "workout-day"
        case .sessionOpen: "session-open"
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
        case .dose: "Medication"
        case .gateFloor: "Readiness floor ⏰"
        case .hrCapCheck: "Check your heart-rate cap"
        case .workoutDay: "Session planned today 🏋️"
        case .sessionOpen: "Session still open"
        }
    }

    public var notificationBody: String {
        switch self {
        case .journal: "Take a minute to reflect on your day."
        case .mind: "A daily check-in takes about 10 seconds."
        case .dose: "Log it in the check-in so the dosing count stays accurate."
        case .gateFloor: "05:10 local — check today's readiness verdict."
        case .hrCapCheck: "Is your cap still right? JI never changes it for you."
        case .workoutDay: "Your plan has a session today. Open the logger when you start."
        case .sessionOpen: "No set logged for 90 minutes. Finish the session or log the next set."
        }
    }

    /// Screen defaults (`reminders.tsx`: journal 21:00, mind 09:00, dose 08:30, floor 05:10).
    public var defaultTime: ReminderTime {
        switch self {
        case .journal: ReminderTime(hour: 21, minute: 0)
        case .mind: ReminderTime(hour: 9, minute: 0)
        case .dose: ReminderTime(hour: 8, minute: 30)   // placeholder only: the medication's own usualTime is what gets scheduled (B-57 W4)
        case .gateFloor: ReminderTime(hour: 5, minute: 10)
        case .hrCapCheck: ReminderTime(hour: 9, minute: 0)
        case .workoutDay: WorkoutNudgePrefs.defaultTime
        case .sessionOpen: ReminderTime(hour: 0, minute: 0)   // not clock-based: 90 min after the last set
        }
    }

    /// Section header + caption, verbatim `reminders.tsx`.
    public var sectionTitle: String {
        switch self {
        case .journal: "Journal reminder"
        case .mind: "Mind check-in reminder"
        case .dose: "Medication"
        case .gateFloor: "Readiness floor"
        case .hrCapCheck: "HR cap check"
        case .workoutDay: "Planned session"
        case .sessionOpen: "Open session"
        }
    }

    public var sectionCaption: String {
        switch self {
        case .journal: "A daily nudge to take a minute and write."
        case .mind: "A separate daily nudge for the mood/stress/energy check-in — own time, own toggle."
        case .dose: "A daily nudge at your medication's time — keeps the readiness gate's consecutive-dosing count accurate."
        case .gateFloor: "A 05:10 local nudge that opens straight into today's readiness rationale."
        case .hrCapCheck: "JI asks whether your cap is still right. It never changes the number for you."
        case .workoutDay: "Only on days your plan has a session, and not once it is logged."
        case .sessionOpen: "90 minutes after your last set while the session is not finished."
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

    let center: any ReminderNotificationCenter   // internal: B-43 P2's extension (WorkoutSessionReminders.swift) uses it

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

    public nonisolated static func request(kind: ReminderKind, time: ReminderTime, today: String,
                                           medication: MedicationEntry? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind.notificationTitle
        content.body = kind.notificationBody
        // B-57 W4: the medication reminder speaks the user's own name, dose and time.
        if kind == .dose, let med = medication, med.isNamed {
            content.title = "Medication · \(med.name.trimmingCharacters(in: .whitespacesAndNewlines))"
            let dose = med.dose.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = formatTime(hour: time.hour, minute: time.minute)
            content.body = (dose.isEmpty ? "At \(at)" : "\(dose) at \(at)") + ". Log it in the check-in so the dosing count stays accurate."
        }
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
    public func schedule(_ kind: ReminderKind, at time: ReminderTime, today: String = Self.todayISO(),
                         medication: MedicationEntry? = nil) async throws {
        cancel(kind)
        try await center.add(Self.request(kind: kind, time: time, today: today, medication: medication))
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

    // MARK: HR cap re-check (B-57 W4) — one-shot, dated, rescheduled on every confirmation

    public nonisolated static func hrCapCheckRequest(due: String, capBpm: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = ReminderKind.hrCapCheck.notificationTitle
        content.body = "Is \(capBpm) bpm still right? JI never changes it for you."
        content.sound = .default
        content.userInfo = [kindKey: ReminderKind.hrCapCheck.tag]
        let parts = due.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if parts.count == 3 { c.year = parts[0]; c.month = parts[1]; c.day = parts[2] }
        let at = ReminderKind.hrCapCheck.defaultTime
        c.hour = at.hour; c.minute = at.minute
        return UNNotificationRequest(identifier: ReminderKind.hrCapCheck.identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
    }

    /// Schedules (replacing) the re-check for 8 weeks after `confirmedOn` (tomorrow if overdue).
    /// Returns the due date.
    @discardableResult
    public func scheduleHrCapCheck(confirmedOn: String, capBpm: Int, today: String = Self.todayISO()) async throws -> String {
        cancelHrCapCheck()
        let due = HrCapRecheck.nextDue(confirmedOn: confirmedOn, today: today)
        try await center.add(Self.hrCapCheckRequest(due: due, capBpm: capBpm))
        return due
    }

    /// W-B102 C-6: drops today's pending data-triggered check-in (`CheckInNotification`).
    public func cancelDataCheckIn() { center.removePendingRequests(withIdentifiers: [CheckInNotification.identifier]) }

    public func cancelHrCapCheck() { center.removePendingRequests(withIdentifiers: [ReminderKind.hrCapCheck.identifier]) }

    /// The pending re-check's due date (yyyy-MM-dd), nil = off.
    public func hrCapCheckDue() async -> String? {
        for r in await center.pendingRequests() where r.identifier == ReminderKind.hrCapCheck.identifier {
            guard let c = (r.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
                  let y = c.year, let m = c.month, let d = c.day else { continue }
            return String(format: "%04d-%02d-%02d", y, m, d)
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

    /// W-FIX6 F6-16: how many reminders are on, read the way the Reminders screen reads them —
    /// each daily kind with a pending request, each scheduled workout day, and the HR-cap re-check.
    /// The Settings row count used saved prefs, which said "1 on" while the screen showed two.
    public func activeCount() async -> Int {
        var n = 0
        for kind in ReminderKind.dailyCases where await scheduledTime(for: kind) != nil { n += 1 }
        n += await allWorkouts().count
        if await hrCapCheckDue() != nil { n += 1 }
        if await !pendingWorkoutDays().isEmpty { n += 1 }   // B-43 P2: the planned-session reminder counts once
        return n
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
    // DayKey exception (D1): user's wall clock — notification triggers fire on the device calendar.
    public nonisolated static func todayISO(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }
}
