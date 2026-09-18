import Foundation
import Testing
import UserNotifications
import JIPersistence
@testable import JIFeatures

// W5a-L2 — the `useReminderToggle` / `WorkoutReminderSection` state machines from
// `mobile/app/reminders.tsx`: toggle on = permission → schedule; toggle off = cancel; changing
// the time while enabled reschedules; permission denied renders RN's copy; prefs persist.

@MainActor
private func makeModel(status: UNAuthorizationStatus = .authorized,
                       prefs: PrefStore? = nil) throws -> (RemindersViewModel, FakeNotificationCenter, PrefStore) {
    let store = try prefs ?? PrefStore(db: AppDatabase.inMemory())
    let center = FakeNotificationCenter(status: status)
    let model = RemindersViewModel(scheduler: ReminderScheduler(center: center), prefs: store, today: { "2026-09-17" })
    return (model, center, store)
}

@Test @MainActor func defaultsMatchRNBeforeAnythingIsScheduled() throws {
    let (m, _, _) = try makeModel()
    #expect(m.daily[.journal]?.time == ReminderTime(hour: 21, minute: 0))
    #expect(m.daily[.mind]?.time == ReminderTime(hour: 9, minute: 0))
    #expect(m.daily[.dose]?.time == ReminderTime(hour: 8, minute: 30))
    #expect(m.daily[.gateFloor]?.time == ReminderTime(hour: 5, minute: 10))
    for kind in ReminderKind.allCases { #expect(m.daily[kind]?.enabled == false) }
    for wd in Weekday.allCases {
        #expect(m.workouts[wd]?.enabled == false)
        #expect(m.workouts[wd]?.time == ReminderTime(hour: 7, minute: 0))
    }
}

@Test @MainActor func toggleOnSchedulesTheExactRequestAndTurnsOffCancelsIt() async throws {
    let (m, c, _) = try makeModel()
    await m.setEnabled(.mind, true)
    #expect(m.daily[.mind]?.enabled == true)
    #expect(m.daily[.mind]?.scheduled == ReminderTime(hour: 9, minute: 0))
    #expect(c.pending.map(\.identifier) == ["ji.reminders.mind-reminder"])
    #expect(m.statusLine(for: .mind) == "Scheduled for 09:00 every day.")
    await m.setEnabled(.mind, false)
    #expect(m.daily[.mind]?.enabled == false)
    #expect(m.daily[.mind]?.scheduled == nil)
    #expect(c.pending.isEmpty)
    #expect(m.statusLine(for: .mind) == "No reminder scheduled.")
}

@Test @MainActor func changingTimeWhileEnabledReschedulesButNotWhileDisabled() async throws {
    let (m, c, _) = try makeModel()
    await m.setHour(.journal, 22)
    #expect(c.pending.isEmpty, "disabled: time edits are local only")
    await m.setEnabled(.journal, true)
    await m.setMinute(.journal, 15)
    let r = try #require(c.pending.first { $0.identifier == "ji.reminders.journal-reminder" })
    let comps = (r.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    #expect(comps?.hour == 22 && comps?.minute == 15)
    #expect(m.daily[.journal]?.scheduled == ReminderTime(hour: 22, minute: 15))
}

@Test @MainActor func hourAndMinuteStepsWrapLikeRNsStepper() async throws {
    let (m, _, _) = try makeModel()
    await m.stepHour(.journal, -1); await m.stepHour(.journal, -1) // 21 → 20 → 19
    #expect(m.daily[.journal]?.time.hour == 19)
    await m.setHour(.journal, 23); await m.stepHour(.journal, 1)
    #expect(m.daily[.journal]?.time.hour == 0)
    await m.stepMinute(.journal, -1) // 0 → 55 (step 5)
    #expect(m.daily[.journal]?.time.minute == 55)
}

@Test @MainActor func permissionDeniedRendersRNsCopyAndSchedulesNothing() async throws {
    let (m, c, _) = try makeModel(status: .notDetermined)
    c.grantOnRequest = false
    await m.setEnabled(.dose, true)
    #expect(m.daily[.dose]?.enabled == false)
    #expect(m.daily[.dose]?.notice == RemindersCopy.permissionDenied)
    #expect(RemindersCopy.permissionDenied == "Notification permission was denied — enable it in system settings to get reminders.")
    #expect(c.pending.isEmpty)
}

@Test @MainActor func loadSurfacesAnAlreadyDeniedPermission() async throws {
    let (m, _, _) = try makeModel(status: .denied)
    await m.load()
    #expect(m.permissionDenied)
    let (m2, _, _) = try makeModel(status: .authorized)
    await m2.load()
    #expect(!m2.permissionDenied)
}

@Test @MainActor func schedulingFailureRendersANoticeAndKeepsToggleOff() async throws {
    let (m, c, _) = try makeModel()
    c.throwOnAdd = true
    await m.setEnabled(.journal, true)
    #expect(m.daily[.journal]?.enabled == false)
    #expect(m.daily[.journal]?.notice == RemindersCopy.unavailable)
}

@Test @MainActor func loadHydratesFromThePendingCentreLikeRNsSourceOfTruth() async throws {
    let (m, c, _) = try makeModel()
    try await c.add(ReminderScheduler.request(kind: .gateFloor, time: ReminderTime(hour: 6, minute: 0), today: "2026-09-17"))
    try await c.add(ReminderScheduler.workoutRequest(weekday: .thursday, time: ReminderTime(hour: 18, minute: 30)))
    await m.load()
    #expect(m.daily[.gateFloor]?.enabled == true)
    #expect(m.daily[.gateFloor]?.time == ReminderTime(hour: 6, minute: 0))
    #expect(m.workouts[.thursday]?.enabled == true)
    #expect(m.workouts[.thursday]?.time == ReminderTime(hour: 18, minute: 30))
    #expect(m.workouts[.monday]?.enabled == false)
}

/// Times persist through `PrefStore`; on/off stays the centre's truth (RN: the pending
/// notification IS the state), so an emptied centre reads back as "off" with the edited time kept.
@Test @MainActor func prefsPersistTimesWhileEnabledFollowsTheCentre() async throws {
    let (m, _, store) = try makeModel()
    await m.setEnabled(.mind, true)
    await m.setHour(.mind, 10)
    await m.setWorkoutEnabled(.monday, true)
    await m.shiftWorkoutTime(.monday, minutes: 15)
    await m.setHour(.dose, 7) // disabled: the chosen time still persists

    let (m2, _, _) = try makeModel(prefs: store)
    await m2.load()
    #expect(m2.daily[.mind]?.enabled == false, "centre is empty for m2 → off")
    #expect(m2.daily[.mind]?.time == ReminderTime(hour: 10, minute: 0))
    #expect(m2.daily[.dose]?.enabled == false)
    #expect(m2.daily[.dose]?.time == ReminderTime(hour: 7, minute: 30))
    #expect(m2.workouts[.monday]?.enabled == false)
    #expect(m2.workouts[.monday]?.time == ReminderTime(hour: 7, minute: 15))
    let raw = try store.get(RemindersPrefs.prefKey, as: RemindersPrefs.self)
    #expect(raw != nil)
}

@Test @MainActor func workoutToggleAndTimeShiftAreIndependentPerWeekday() async throws {
    let (m, c, _) = try makeModel()
    await m.setWorkoutEnabled(.monday, true)
    await m.setWorkoutEnabled(.thursday, true)
    await m.shiftWorkoutTime(.thursday, minutes: -15) // 07:00 → 06:45, rescheduled
    #expect(m.workouts[.monday]?.time == ReminderTime(hour: 7, minute: 0))
    #expect(m.workouts[.thursday]?.time == ReminderTime(hour: 6, minute: 45))
    let thu = try #require(c.pending.first { $0.identifier == "ji.reminders.workout-reminder.5" })
    let comps = (thu.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    #expect(comps?.hour == 6 && comps?.minute == 45 && comps?.weekday == 5)
    await m.setWorkoutEnabled(.monday, false)
    #expect(c.pending.map(\.identifier) == ["ji.reminders.workout-reminder.5"])
    #expect(m.workoutTimeLabel(.thursday) == "06:45")
}

@Test @MainActor func workoutTimeWrapsAcrossMidnight() async throws {
    let (m, _, _) = try makeModel()
    await m.shiftWorkoutTime(.sunday, minutes: -7 * 60 - 15) // 07:00 − 7h15 → 23:45
    #expect(m.workouts[.sunday]?.time == ReminderTime(hour: 23, minute: 45))
}

@Test @MainActor func remindersSectionIsRegisteredInTheDataBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(RemindersSection.sectionId))
    let section = SettingsRegistry.sections.first { $0.id == RemindersSection.sectionId }
    #expect(SettingsGroup(sortKey: section?.sortKey ?? -1) == .data)
}
