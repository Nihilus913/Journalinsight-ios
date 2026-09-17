import Foundation
import Testing
import UserNotifications
@testable import JIFeatures

// W5a-L2 (P-reminders) — ports the schedule/cancel/get logic of
// `mobile/__tests__/notify/reminders.test.ts` against a fake notification centre. RN tags every
// request with `content.data.kind` (+ `weekday` for workouts) and identifies "ours" by that tag;
// Swift keeps the same tag in `userInfo` AND gives each one a deterministic identifier (UN needs
// one; expo minted them), so "cancel only this kind" holds by identifier and by tag alike.

@MainActor
private func makeScheduler(status: UNAuthorizationStatus = .authorized) -> (ReminderScheduler, FakeNotificationCenter) {
    let center = FakeNotificationCenter(status: status)
    return (ReminderScheduler(center: center), center)
}

private func components(_ r: UNNotificationRequest) -> DateComponents? {
    (r.trigger as? UNCalendarNotificationTrigger)?.dateComponents
}

// ---- pure ------------------------------------------------------------------------------------

@Test func formatTimeZeroPadsToHHMM() {
    #expect(ReminderScheduler.formatTime(hour: 9, minute: 5) == "09:05")
    #expect(ReminderScheduler.formatTime(hour: 21, minute: 0) == "21:00")
}

@Test func isValidTimeRejectsOutOfRange() {
    #expect(ReminderScheduler.isValidTime(hour: 0, minute: 0))
    #expect(ReminderScheduler.isValidTime(hour: 23, minute: 59))
    #expect(!ReminderScheduler.isValidTime(hour: 24, minute: 0))
    #expect(!ReminderScheduler.isValidTime(hour: -1, minute: 0))
    #expect(!ReminderScheduler.isValidTime(hour: 0, minute: 60))
}

@Test func weekdaysListMonToSunUsingOneEqualsSundayNumbering() {
    #expect(Weekday.displayOrder.map(\.rawValue) == [2, 3, 4, 5, 6, 7, 1])
    #expect(Weekday.sunday.label == "Sunday" && Weekday.sunday.shortLabel == "Sun")
    #expect(Weekday.saturday.rawValue == 7)
}

@Test func wrapMinutesOfDayWrapsAtMidnight() {
    #expect(ReminderScheduler.wrapMinutesOfDay(23 * 60 + 50 + 15) == 5)
    #expect(ReminderScheduler.wrapMinutesOfDay(0 - 15) == 24 * 60 - 15)
}

@Test func dailyRequestCarriesRNKindTagTitleBodyAndRepeatingCalendarTrigger() {
    let r = ReminderScheduler.request(kind: .journal, time: ReminderTime(hour: 21, minute: 0), today: "2026-09-17")
    #expect(r.identifier == "ji.reminders.journal-reminder")
    #expect(r.content.title == "Time to journal ✍️")
    #expect(r.content.body == "Take a minute to reflect on your day.")
    #expect(r.content.userInfo["kind"] as? String == "journal-reminder")
    let t = try? #require(r.trigger as? UNCalendarNotificationTrigger)
    #expect(t?.repeats == true)
    #expect(t?.dateComponents.hour == 21 && t?.dateComponents.minute == 0)
    #expect(t?.dateComponents.weekday == nil)
}

@Test func gateFloorRequestReusesLocalVerdictFloorIdentifierAndEmbedsTodaysDeepLink() {
    // The 05:10 floor is ONE pending request: the app schedules it under
    // `LocalVerdictFloor.identifier` at launch; toggling it here must replace/cancel that same one.
    let r = ReminderScheduler.request(kind: .gateFloor, time: ReminderKind.gateFloor.defaultTime, today: "2026-09-17")
    #expect(r.identifier == "ji.notifications.verdict-floor")
    #expect(r.content.userInfo["kind"] as? String == "gate-floor")
    #expect(r.content.userInfo["url"] as? String == "ji://gate?date=2026-09-17")
    #expect(components(r)?.hour == 5 && components(r)?.minute == 10)
}

@Test func workoutRequestCarriesWeekdayTagAndWeeklyTrigger() {
    let r = ReminderScheduler.workoutRequest(weekday: .monday, time: ReminderTime(hour: 7, minute: 0))
    #expect(r.identifier == "ji.reminders.workout-reminder.2")
    #expect(r.content.title == "Workout time 🏋️")
    #expect(r.content.userInfo["kind"] as? String == "workout-reminder")
    #expect(r.content.userInfo["weekday"] as? Int == 2)
    #expect(components(r)?.weekday == 2 && components(r)?.hour == 7 && components(r)?.minute == 0)
}

// ---- daily reminders ---------------------------------------------------------------------------

@Test @MainActor func scheduleCancelsTheExistingReminderOfThatKindBeforeScheduling() async throws {
    let (s, c) = makeScheduler()
    try await s.schedule(.journal, at: ReminderTime(hour: 21, minute: 0))
    try await s.schedule(.journal, at: ReminderTime(hour: 22, minute: 30))
    #expect(c.pending.count == 1)
    #expect(c.removed.contains("ji.reminders.journal-reminder"))
    #expect(await s.scheduledTime(for: .journal) == ReminderTime(hour: 22, minute: 30))
}

@Test @MainActor func cancelRemovesOnlyThatKindLeavingOthersScheduled() async throws {
    let (s, c) = makeScheduler()
    try await s.schedule(.journal, at: ReminderTime(hour: 21, minute: 0))
    try await s.schedule(.mind, at: ReminderTime(hour: 9, minute: 0))
    try await s.schedule(.dose, at: ReminderTime(hour: 8, minute: 30))
    s.cancel(.mind)
    #expect(c.pending.map(\.identifier).sorted() == ["ji.reminders.dose-reminder", "ji.reminders.journal-reminder"])
    #expect(await s.scheduledTime(for: .mind) == nil)
    #expect(await s.scheduledTime(for: .journal) == ReminderTime(hour: 21, minute: 0))
    #expect(await s.scheduledTime(for: .dose) == ReminderTime(hour: 8, minute: 30))
}

@Test @MainActor func scheduledTimeIsNilWhenNothingOfThatKindIsPending() async {
    let (s, _) = makeScheduler()
    #expect(await s.scheduledTime(for: .gateFloor) == nil)
}

@Test @MainActor func scheduledTimeIgnoresForeignRequestsWithoutOurKindTag() async {
    let (s, c) = makeScheduler()
    let content = UNMutableNotificationContent()
    content.title = "someone else"
    c.pending.append(UNNotificationRequest(identifier: "other", content: content,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 1, minute: 2), repeats: true)))
    #expect(await s.scheduledTime(for: .journal) == nil)
    s.cancel(.journal)
    #expect(c.pending.count == 1, "cancel leaves foreign requests untouched")
}

// ---- workouts ----------------------------------------------------------------------------------

@Test @MainActor func schedulingOneWeekdayNeverTouchesAnother() async throws {
    let (s, c) = makeScheduler()
    try await s.scheduleWorkout(.monday, at: ReminderTime(hour: 7, minute: 0))
    try await s.scheduleWorkout(.thursday, at: ReminderTime(hour: 18, minute: 15))
    try await s.scheduleWorkout(.monday, at: ReminderTime(hour: 6, minute: 45))
    #expect(c.pending.count == 2)
    let all = await s.allWorkouts()
    #expect(all[.monday] == ReminderTime(hour: 6, minute: 45))
    #expect(all[.thursday] == ReminderTime(hour: 18, minute: 15))
    #expect(all[.sunday] == nil)
}

@Test @MainActor func cancelWorkoutRemovesOnlyThatWeekdayAndLeavesDailyReminders() async throws {
    let (s, c) = makeScheduler()
    try await s.schedule(.journal, at: ReminderTime(hour: 21, minute: 0))
    try await s.scheduleWorkout(.monday, at: ReminderTime(hour: 7, minute: 0))
    try await s.scheduleWorkout(.friday, at: ReminderTime(hour: 7, minute: 0))
    s.cancelWorkout(.monday)
    #expect(c.pending.map(\.identifier).sorted() == ["ji.reminders.journal-reminder", "ji.reminders.workout-reminder.6"])
}

@Test @MainActor func allWorkoutsIsEmptyWhenNothingScheduled() async {
    let (s, _) = makeScheduler()
    #expect(await s.allWorkouts().isEmpty)
}

// ---- permission ------------------------------------------------------------------------------

@Test @MainActor func requestPermissionIsTrueWhenAlreadyAuthorizedWithoutPrompting() async {
    let (s, c) = makeScheduler(status: .authorized)
    #expect(await s.requestPermission())
    #expect(c.authorizationRequests == 0)
}

@Test @MainActor func requestPermissionPromptsWhenNotDeterminedAndReturnsTheAnswer() async {
    let (s, c) = makeScheduler(status: .notDetermined)
    c.grantOnRequest = true
    #expect(await s.requestPermission())
    #expect(c.authorizationRequests == 1)
    let (s2, c2) = makeScheduler(status: .notDetermined)
    c2.grantOnRequest = false
    #expect(await s2.requestPermission() == false)
}

@Test @MainActor func requestPermissionNeverThrowsWhenTheCentreDoes() async {
    let (s, c) = makeScheduler(status: .notDetermined)
    c.throwOnRequest = true
    #expect(await s.requestPermission() == false)
}
