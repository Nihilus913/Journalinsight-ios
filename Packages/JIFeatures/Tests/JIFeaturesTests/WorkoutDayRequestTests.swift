import Foundation
import Testing
import UserNotifications
import JICore
import JIPersistence
@testable import JIFeatures

// RG-65 (B-43): a cardio day's "session planned today" nudge must open Training, not the strength
// set logger (`ji://strength-log`). Only strength days deep-link into the logger.

@MainActor @Suite(.serialized) struct WorkoutDayRequestTests {
    let db: AppDatabase
    let prefs: PrefStore
    let center = FakeNotificationCenter()
    let today = "2030-01-07"
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        db = try AppDatabase.inMemory()
        prefs = PrefStore(db: db)
    }

    func day(_ wd: Int, _ date: String, _ kind: TrainingWeekDayKind, name: String? = nil) -> TrainingWeekDay {
        TrainingWeekDay(weekday: wd, date: date, kind: kind, sessionName: name, sessionId: nil, done: nil, isToday: date == today)
    }

    var week: TrainingWeekSummary {
        TrainingWeekSummary(days: [
            day(0, "2030-01-07", .strength, name: "Upper A"),
            day(1, "2030-01-08", .rest),
            day(2, "2030-01-09", .interval, name: "Intervals"),
            day(6, "2030-01-13", .longRun, name: "Long Run Zone 2"),
        ], planTotal: 1, assigned: 1, planDone: nil, next: nil)
    }

    func link(_ r: UNNotificationRequest?) -> String? { r?.content.userInfo[ReminderScheduler.deepLinkURLKey] as? String }

    @Test func strengthDayLinksToTheLoggerCardioDaysToTraining() {
        let t = WorkoutNudgePrefs.defaultTime
        #expect(link(ReminderScheduler.workoutDayRequest(date: today, sessionName: "Upper A", time: t, kind: .strength)) == "ji://strength-log")
        #expect(link(ReminderScheduler.workoutDayRequest(date: today, sessionName: "Intervals", time: t, kind: .interval)) == "ji://training")
        #expect(link(ReminderScheduler.workoutDayRequest(date: today, sessionName: "Long Run", time: t, kind: .longRun)) == "ji://training")
        // Unknown kind (old prefs without kinds) never opens the logger.
        #expect(link(ReminderScheduler.workoutDayRequest(date: today, sessionName: nil, time: t)) == "ji://training")
    }

    @Test func weekChangedLaysKindAwareLinks() async {
        var p = WorkoutNudgePrefs(); p.workoutDayEnabled = true; p.save(prefs)
        let t = now, d = today
        let nudges = WorkoutSessionReminders(scheduler: ReminderScheduler(center: center), prefs: prefs, now: { t }, today: { d })
        await nudges.weekChanged(week)
        let byId = Dictionary(uniqueKeysWithValues: center.pending.map { ($0.identifier, $0) })
        #expect(link(byId["ji.reminders.workout-day.2030-01-07"]) == "ji://strength-log")
        #expect(link(byId["ji.reminders.workout-day.2030-01-09"]) == "ji://training")
        #expect(link(byId["ji.reminders.workout-day.2030-01-13"]) == "ji://training")
        #expect(WorkoutNudgePrefs.load(prefs).plannedKinds == ["2030-01-07": "S", "2030-01-09": "I", "2030-01-13": "R"])
    }
}
