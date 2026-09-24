import Foundation
import Observation
import JIPersistence

// W5a-L2 — `useReminderToggle` (×4) + `WorkoutReminderSection`'s 7-row matrix from
// `mobile/app/reminders.tsx`, one `@Observable` model. The pending notification is the on/off +
// time source of truth (RN has no persistence layer); Swift additionally mirrors the chosen
// state into `PrefStore` (`reminders.prefs`) so a disabled reminder keeps its edited time across
// launches and other surfaces can read "floor reminder off" without a centre scan.

/// Notice copy, verbatim RN.
public nonisolated enum RemindersCopy {
    public static let permissionDenied = "Notification permission was denied — enable it in system settings to get reminders."
    public static let unavailable = "Something about notifications isn't available here (Expo Go has limited support). Try a development build."
    public static let schedulingUnavailable = "Scheduling isn't available here (Expo Go has limited notification support). Try a development build."
    public static let readFailed = "Couldn't read scheduled reminders on this device."
    /// B-57 W1: the board's subtitle (5 Settings/08); the layout rework (medication, cap check) is W4.
    public static let header = "Quiet by default. Only what you asked for."
    public static let workoutTitle = "Workout reminders"
    public static let workoutCaption = "Independent on/off + time per weekday — separate from the reminders above."
    public static let noReminder = "No reminder scheduled."
}

public nonisolated struct RemindersPrefs: Codable, Equatable, Sendable {
    public static let prefKey = "reminders.prefs"
    public nonisolated struct Entry: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var time: ReminderTime
        public init(enabled: Bool, time: ReminderTime) { self.enabled = enabled; self.time = time }
    }
    /// Keyed by `ReminderKind.rawValue` / `Weekday.rawValue` as strings (JSON-object friendly).
    public var daily: [String: Entry] = [:]
    public var workouts: [String: Entry] = [:]
    public init() {}
}

@Observable
public final class RemindersViewModel {
    public struct DailyState: Equatable {
        public var enabled = false
        public var time: ReminderTime
        /// What the centre actually has (RN `scheduled`); nil = "No reminder scheduled."
        public var scheduled: ReminderTime?
        public var notice: String?
        public var busy = false
    }

    public struct WorkoutState: Equatable {
        public var enabled = false
        public var time = RemindersViewModel.defaultWorkoutTime
        public var busy = false
    }

    public static let defaultWorkoutTime = ReminderTime(hour: 7, minute: 0)
    /// RN `TIME_STEP_MIN` — quarter-hour granularity for the 7-row matrix.
    public static let workoutStepMinutes = 15
    public static let minuteStep = 5

    public private(set) var daily: [ReminderKind: DailyState]
    public private(set) var workouts: [Weekday: WorkoutState]
    public private(set) var workoutNotice: String?
    /// Authorization is `.denied` at load — RN's denied copy rendered as a screen-level banner.
    public private(set) var permissionDenied = false
    public private(set) var loaded = false

    private let scheduler: ReminderScheduler
    private let prefs: PrefStore
    private let today: () -> String

    public init(scheduler: ReminderScheduler, prefs: PrefStore, today: @escaping () -> String = { ReminderScheduler.todayISO() }) {
        self.scheduler = scheduler
        self.prefs = prefs
        self.today = today
        var daily: [ReminderKind: DailyState] = [:]
        for kind in ReminderKind.allCases { daily[kind] = DailyState(time: kind.defaultTime) }
        self.daily = daily
        var workouts: [Weekday: WorkoutState] = [:]
        for wd in Weekday.allCases { workouts[wd] = WorkoutState() }
        self.workouts = workouts
    }

    // MARK: load

    /// Prefs first (edited-but-disabled times), then the centre wins for anything pending.
    public func load() async {
        if let saved = try? prefs.get(RemindersPrefs.prefKey, as: RemindersPrefs.self) {
            for kind in ReminderKind.allCases {
                if let e = saved.daily[kind.rawValue] { daily[kind]?.enabled = e.enabled; daily[kind]?.time = e.time }
            }
            for wd in Weekday.allCases {
                if let e = saved.workouts[String(wd.rawValue)] { workouts[wd]?.enabled = e.enabled; workouts[wd]?.time = e.time }
            }
        }
        for kind in ReminderKind.allCases {
            if let current = await scheduler.scheduledTime(for: kind) {
                daily[kind]?.scheduled = current
                daily[kind]?.enabled = true
                daily[kind]?.time = current
            } else {
                daily[kind]?.scheduled = nil
                daily[kind]?.enabled = false
            }
        }
        let all = await scheduler.allWorkouts()
        for wd in Weekday.allCases {
            if let t = all[wd] { workouts[wd]?.enabled = true; workouts[wd]?.time = t } else { workouts[wd]?.enabled = false }
        }
        permissionDenied = await scheduler.isDenied()
        loaded = true
    }

    // MARK: daily

    public func statusLine(for kind: ReminderKind) -> String {
        guard let s = daily[kind]?.scheduled else { return RemindersCopy.noReminder }
        return "Scheduled for \(ReminderScheduler.formatTime(hour: s.hour, minute: s.minute)) every day."
    }

    public func setEnabled(_ kind: ReminderKind, _ next: Bool) async {
        guard var state = daily[kind] else { return }
        state.busy = true; state.notice = nil; daily[kind] = state
        defer { daily[kind]?.busy = false; persist() }
        do {
            if next {
                guard await scheduler.requestPermission() else {
                    daily[kind]?.notice = RemindersCopy.permissionDenied
                    permissionDenied = await scheduler.isDenied()
                    return
                }
                try await scheduler.schedule(kind, at: state.time, today: today())
                daily[kind]?.scheduled = state.time
                daily[kind]?.enabled = true
            } else {
                scheduler.cancel(kind)
                daily[kind]?.scheduled = nil
                daily[kind]?.enabled = false
            }
        } catch {
            daily[kind]?.notice = RemindersCopy.unavailable
        }
    }

    public func setHour(_ kind: ReminderKind, _ hour: Int) async {
        guard var t = daily[kind]?.time else { return }
        t.hour = wrap(hour, min: 0, max: 23)
        await setTime(kind, t)
    }

    public func setMinute(_ kind: ReminderKind, _ minute: Int) async {
        guard var t = daily[kind]?.time else { return }
        t.minute = wrap(minute, min: 0, max: 59)
        await setTime(kind, t)
    }

    /// RN `Stepper`: hour step 1, wraps 0…23.
    public func stepHour(_ kind: ReminderKind, _ direction: Int) async {
        guard let t = daily[kind]?.time else { return }
        await setHour(kind, t.hour + direction)
    }

    /// RN `Stepper`: minute step 5, wraps 0…59.
    public func stepMinute(_ kind: ReminderKind, _ direction: Int) async {
        guard let t = daily[kind]?.time else { return }
        await setMinute(kind, t.minute + direction * Self.minuteStep)
    }

    private func setTime(_ kind: ReminderKind, _ time: ReminderTime) async {
        daily[kind]?.time = time
        if daily[kind]?.enabled == true { await applySchedule(kind, time) }
        persist()
    }

    private func applySchedule(_ kind: ReminderKind, _ time: ReminderTime) async {
        daily[kind]?.busy = true; daily[kind]?.notice = nil
        defer { daily[kind]?.busy = false }
        do {
            try await scheduler.schedule(kind, at: time, today: today())
            daily[kind]?.scheduled = time
            daily[kind]?.enabled = true
        } catch {
            daily[kind]?.notice = RemindersCopy.schedulingUnavailable
        }
    }

    private func wrap(_ v: Int, min: Int, max: Int) -> Int {
        let span = max - min + 1
        return min + (((v - min) % span) + span) % span
    }

    // MARK: workouts

    public func workoutTimeLabel(_ weekday: Weekday) -> String {
        let t = workouts[weekday]?.time ?? Self.defaultWorkoutTime
        return ReminderScheduler.formatTime(hour: t.hour, minute: t.minute)
    }

    public func setWorkoutEnabled(_ weekday: Weekday, _ next: Bool) async {
        guard let state = workouts[weekday] else { return }
        workouts[weekday]?.busy = true; workoutNotice = nil
        defer { workouts[weekday]?.busy = false; persist() }
        do {
            if next {
                guard await scheduler.requestPermission() else {
                    workoutNotice = RemindersCopy.permissionDenied
                    permissionDenied = await scheduler.isDenied()
                    return
                }
                try await scheduler.scheduleWorkout(weekday, at: state.time)
                workouts[weekday]?.enabled = true
            } else {
                scheduler.cancelWorkout(weekday)
                workouts[weekday]?.enabled = false
            }
        } catch {
            workoutNotice = RemindersCopy.unavailable
        }
    }

    /// RN `onChangeTime(wd, ±TIME_STEP_MIN)`: wraps across midnight; reschedules only if enabled.
    public func shiftWorkoutTime(_ weekday: Weekday, minutes delta: Int) async {
        guard let cur = workouts[weekday] else { return }
        let total = ReminderScheduler.wrapMinutesOfDay(cur.time.hour * 60 + cur.time.minute + delta)
        let time = ReminderTime(hour: total / 60, minute: total % 60)
        workouts[weekday]?.time = time
        if cur.enabled {
            workouts[weekday]?.busy = true; workoutNotice = nil
            do {
                try await scheduler.scheduleWorkout(weekday, at: time)
                workouts[weekday]?.enabled = true
            } catch {
                workoutNotice = RemindersCopy.schedulingUnavailable
            }
            workouts[weekday]?.busy = false
        }
        persist()
    }

    // MARK: prefs

    private func persist() {
        var p = RemindersPrefs()
        for (kind, s) in daily { p.daily[kind.rawValue] = .init(enabled: s.enabled, time: s.time) }
        for (wd, s) in workouts { p.workouts[String(wd.rawValue)] = .init(enabled: s.enabled, time: s.time) }
        try? prefs.set(RemindersPrefs.prefKey, p)
    }
}
