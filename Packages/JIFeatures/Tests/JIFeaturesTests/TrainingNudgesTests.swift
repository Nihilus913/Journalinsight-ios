import Foundation
import Testing
import UserNotifications
import JICore
import JIPersistence
@testable import JIFeatures

// B-43 P2 — workoutDay (planned session today, 17:30, off until toggled) and sessionOpen (90 min
// after the last set) reminders; both cancelled when the session ends.

@MainActor @Suite(.serialized) struct TrainingNudgesTests {
    let db: AppDatabase
    let prefs: PrefStore
    let center = FakeNotificationCenter()
    // Far-future week so the calendar triggers are always ahead of the real clock.
    let today = "2030-01-07"   // a Monday
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        db = try AppDatabase.inMemory()
        prefs = PrefStore(db: db)
    }

    var scheduler: ReminderScheduler { ReminderScheduler(center: center) }

    func day(_ wd: Int, _ date: String, _ kind: TrainingWeekDayKind, name: String? = nil, done: Bool? = nil) -> TrainingWeekDay {
        TrainingWeekDay(weekday: wd, date: date, kind: kind, sessionName: name, sessionId: nil, done: done, isToday: date == today)
    }

    var week: TrainingWeekSummary {
        TrainingWeekSummary(days: [
            day(0, "2030-01-07", .strength, name: "Upper A"),
            day(1, "2030-01-08", .rest),
            day(2, "2030-01-09", .interval, name: "Intervals"),
            day(3, "2030-01-10", .rest),
            day(4, "2030-01-11", .strength, name: "Lower A", done: true),
            day(5, "2030-01-12", .rest),
            day(6, "2030-01-13", .longRun),
        ], planTotal: 2, assigned: 2, planDone: nil, next: nil)
    }

    func nudges() -> WorkoutSessionReminders {
        let t = now, d = today
        return WorkoutSessionReminders(scheduler: scheduler, prefs: prefs, now: { t }, today: { d })
    }

    func model() -> RemindersViewModel {
        let t = now, d = today
        return RemindersViewModel(scheduler: scheduler, prefs: prefs, today: { d }, now: { t })
    }

    var workoutDayIds: [String] {
        center.pending.map(\.identifier).filter { $0.hasPrefix("ji.reminders.workout-day.") }.sorted()
    }

    // MARK: pure

    @Test func plannedDaysAreSessionDaysTodayOrLaterNotDone() {
        let days = ReminderScheduler.plannedWorkoutDays(week, today: "2030-01-08")
        #expect(days == ["2030-01-09": "Intervals", "2030-01-13": ""])
        #expect(ReminderScheduler.plannedWorkoutDays(week, today: today, doneDate: "2030-01-07").keys.sorted() == ["2030-01-09", "2030-01-13"])
        #expect(ReminderScheduler.plannedWorkoutDays(nil, today: today).isEmpty)
    }

    @Test func workoutDayRequestIsADatedOneShotAt1730WithTheLoggerLink() throws {
        let r = try #require(ReminderScheduler.workoutDayRequest(date: "2030-01-07", sessionName: "Upper A", time: WorkoutNudgePrefs.defaultTime, kind: .strength))
        #expect(r.identifier == "ji.reminders.workout-day.2030-01-07")
        let trig = try #require(r.trigger as? UNCalendarNotificationTrigger)
        #expect(!trig.repeats)
        #expect(trig.dateComponents.year == 2030 && trig.dateComponents.month == 1 && trig.dateComponents.day == 7)
        #expect(trig.dateComponents.hour == 17 && trig.dateComponents.minute == 30)
        #expect(r.content.body.contains("Upper A"))
        #expect(r.content.userInfo[ReminderScheduler.deepLinkURLKey] as? String == ReminderScheduler.strengthLogURL)
        #expect(ReminderScheduler.workoutDayRequest(date: "bad", sessionName: nil, time: WorkoutNudgePrefs.defaultTime) == nil)
    }

    @Test func defaultsAreOffAt1730AndSessionOpenOn() {
        let p = WorkoutNudgePrefs.load(prefs)
        #expect(!p.workoutDayEnabled && p.workoutDayTime == ReminderTime(hour: 17, minute: 30) && p.sessionOpenEnabled)
        #expect(!ReminderKind.dailyCases.contains(.workoutDay) && !ReminderKind.dailyCases.contains(.sessionOpen))
    }

    // MARK: workoutDay

    @Test func weekChangeWhileDisabledSchedulesNothingButCachesThePlan() async {
        await nudges().weekChanged(week)
        #expect(workoutDayIds.isEmpty)
        #expect(WorkoutNudgePrefs.load(prefs).planned.keys.sorted() == ["2030-01-07", "2030-01-09", "2030-01-13"])
    }

    @Test func enabledSchedulesOnlyPlannedDays() async {
        let m = model()
        await m.load()
        await nudges().weekChanged(week)
        await m.setWorkoutDayEnabled(true)
        #expect(workoutDayIds == ["ji.reminders.workout-day.2030-01-07", "ji.reminders.workout-day.2030-01-09",
                                  "ji.reminders.workout-day.2030-01-13"])
        #expect(m.workoutDayStatusLine == "Next: 2030-01-07 · 17:30")
        // no rest day, no done day
        #expect(!workoutDayIds.contains { $0.hasSuffix("2030-01-08") || $0.hasSuffix("2030-01-11") })
        // the week summary changing re-lays them
        await nudges().weekChanged(TrainingWeekSummary(days: [day(2, "2030-01-09", .strength, name: "Upper B")],
                                                       planTotal: 1, assigned: 1, planDone: nil, next: nil))
        #expect(workoutDayIds == ["ji.reminders.workout-day.2030-01-09"])
    }

    @Test func disablingCancelsEveryWorkoutDay() async {
        let m = model()
        await nudges().weekChanged(week)
        await m.setWorkoutDayEnabled(true)
        #expect(!workoutDayIds.isEmpty)
        await m.setWorkoutDayEnabled(false)
        #expect(workoutDayIds.isEmpty)
        #expect(m.workoutDayStatusLine == "Off")
    }

    @Test func timeShiftReschedulesAndPersists() async throws {
        let m = model()
        await nudges().weekChanged(week)
        await m.setWorkoutDayEnabled(true)
        await m.shiftWorkoutDayTime(minutes: 15)
        let r = try #require(center.pending.first { $0.identifier == "ji.reminders.workout-day.2030-01-07" })
        let c = try #require((r.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        #expect(c.hour == 17 && c.minute == 45)
        // a fresh screen reads the toggles back from prefs
        let again = model()
        await again.load()
        #expect(again.trainingNudges.workoutDayEnabled && again.trainingNudges.workoutDayTime == ReminderTime(hour: 17, minute: 45))
        #expect(again.workoutDayTimeLabel == "17:45")
    }

    @Test func permissionDeniedLeavesItOff() async {
        center.status = .denied
        center.grantOnRequest = false
        let m = model()
        await nudges().weekChanged(week)
        await m.setWorkoutDayEnabled(true)
        #expect(!m.trainingNudges.workoutDayEnabled && workoutDayIds.isEmpty)
        #expect(m.trainingNotice == RemindersCopy.permissionDenied)
    }

    @Test func pastFireTimesAreSkipped() async {
        let days = await scheduler.scheduleWorkoutDays(["2020-01-01": "Old", "2030-01-09": "New"], at: WorkoutNudgePrefs.defaultTime)
        #expect(days == ["2030-01-09"])
    }

    @Test func workoutDayCountsInTheSettingsRow() async {
        await nudges().weekChanged(week)
        #expect(await scheduler.activeCount() == 0)
        await model().setWorkoutDayEnabled(true)
        #expect(await scheduler.activeCount() == 1)
    }

    // MARK: sessionOpen

    @Test func sessionOpenIs90MinAfterTheLastSetAndMovesWithEachSet() async throws {
        let n = nudges()
        await n.setLogged(at: now.addingTimeInterval(-600))
        let r = try #require(center.pending.first { $0.identifier == ReminderKind.sessionOpen.identifier })
        #expect((r.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == TimeInterval(90 * 60 - 600))
        #expect(!(r.trigger as? UNTimeIntervalNotificationTrigger)!.repeats)
        await n.setLogged(at: now)
        let ids = center.pending.map(\.identifier).filter { $0 == ReminderKind.sessionOpen.identifier }
        #expect(ids.count == 1)
        #expect((center.pending.first { $0.identifier == ReminderKind.sessionOpen.identifier }?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == TimeInterval(90 * 60))
    }

    @Test func sessionOpenDisabledSchedulesNothing() async {
        await model().setSessionOpenEnabled(false)
        await nudges().setLogged(at: now)
        #expect(!center.pending.contains { $0.identifier == ReminderKind.sessionOpen.identifier })
        #expect(!WorkoutNudgePrefs.load(prefs).sessionOpenEnabled)
    }

    @Test func sessionEndCancelsSessionOpenAndTodaysWorkoutDay() async {
        let m = model()
        let n = nudges()
        await n.weekChanged(week)
        await m.setWorkoutDayEnabled(true)
        await n.setLogged(at: now)
        await n.sessionEnded(date: "2030-01-07")
        #expect(!center.pending.contains { $0.identifier == ReminderKind.sessionOpen.identifier })
        #expect(workoutDayIds == ["ji.reminders.workout-day.2030-01-09", "ji.reminders.workout-day.2030-01-13"])
        // a later week refresh does not bring back the trained day
        await n.weekChanged(week)
        #expect(!workoutDayIds.contains("ji.reminders.workout-day.2030-01-07"))
    }

    // MARK: the phone logger

    @Test func loggerSchedulesOnSetAndCancelsOnComplete() async throws {
        let n = nudges()
        await n.weekChanged(week)
        await model().setWorkoutDayEnabled(true)
        let t = now
        let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8",
                                    currentKg: 50, stepKg: 2.5, nextKg: 50)
        let log = StrengthLogViewModel(lifts: [bench], sessionId: 1, sessionName: "Upper A", store: StrengthSessionLogStore(db: db),
                                       outbox: nil, provider: nil, prefs: prefs, today: { "2030-01-07" }, now: { t }, reminders: n)
        try #require(log.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) != nil)
        await log.reminderTask?.value
        #expect(center.pending.contains { $0.identifier == ReminderKind.sessionOpen.identifier })
        await log.complete()
        #expect(!center.pending.contains { $0.identifier == ReminderKind.sessionOpen.identifier })
        #expect(!workoutDayIds.contains("ji.reminders.workout-day.2030-01-07"))
    }
}
