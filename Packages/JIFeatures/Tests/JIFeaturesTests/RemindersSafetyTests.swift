import Foundation
import Testing
import UserNotifications
import JIPersistence
@testable import JIFeatures

@MainActor
private func makeSafety(prefs: PrefStore? = nil) throws -> (RemindersViewModel, FakeNotificationCenter, PrefStore) {
    let store = try prefs ?? PrefStore(db: AppDatabase.inMemory())
    let center = FakeNotificationCenter()
    return (RemindersViewModel(scheduler: ReminderScheduler(center: center), prefs: store, today: { "2026-09-24" }), center, store)
}

@MainActor struct RemindersSafetyTests {
    @Test func hrCapCheckIsNotADailyReminder() {
        #expect(!ReminderKind.dailyCases.contains(.hrCapCheck))
        #expect(ReminderKind.dailyCases == [.journal, .mind, .dose, .gateFloor])
        #expect(ReminderKind.dose.sectionTitle == "Medication")
        #expect(ReminderKind.hrCapCheck.sectionTitle == "HR cap check")
    }

    @Test func hrCapCheckFiresOnceAt0900EightWeeksOut() async throws {
        let center = FakeNotificationCenter()
        let s = ReminderScheduler(center: center)
        let due = try await s.scheduleHrCapCheck(confirmedOn: "2026-09-24", capBpm: 168, today: "2026-09-24")
        #expect(due == "2026-11-19")
        let r = try #require(center.pending.first { $0.identifier == ReminderKind.hrCapCheck.identifier })
        let trig = try #require(r.trigger as? UNCalendarNotificationTrigger)
        #expect(!trig.repeats)
        #expect(trig.dateComponents.year == 2026 && trig.dateComponents.month == 11 && trig.dateComponents.day == 19)
        #expect(trig.dateComponents.hour == 9 && trig.dateComponents.minute == 0)
        #expect(r.content.body == "Is 168 bpm still right? JI never changes it for you.")
        #expect(await s.hrCapCheckDue() == "2026-11-19")
        #expect(await s.scheduledTime(for: .dose) == nil)          // never mistaken for a daily one
        s.cancelHrCapCheck()
        #expect(await s.hrCapCheckDue() == nil)
    }

    @Test func medicationReminderUsesTheUsersNameDoseAndTime() {
        let med = MedicationEntry(name: "Concerta", dose: "36 mg", usualTime: ReminderTime(hour: 7, minute: 45))
        let r = ReminderScheduler.request(kind: .dose, time: ReminderTime(hour: 7, minute: 45), today: "2026-09-24", medication: med)
        #expect(r.content.title == "Medication · Concerta")
        #expect(r.content.body == "36 mg at 07:45. Log it in the check-in so the dosing count stays accurate.")
        #expect(!r.content.title.contains("💊"))
        let noDose = ReminderScheduler.request(kind: .dose, time: ReminderTime(hour: 7, minute: 45), today: "2026-09-24",
                                               medication: MedicationEntry(name: "Ritalin", usualTime: ReminderTime(hour: 7, minute: 45)))
        #expect(noDose.content.body == "At 07:45. Log it in the check-in so the dosing count stays accurate.")
        #expect(ReminderScheduler.request(kind: .dose, time: ReminderTime(hour: 8, minute: 0), today: "2026-09-24").content.title == "Medication")
    }

    /// Review Focus 5.
    @Test func doseReminderNeedsAMedicationTime() async throws {
        let (m, c, _) = try makeSafety()
        await m.load()
        await m.setEnabled(.dose, true)
        #expect(m.daily[.dose]?.enabled == false)
        #expect(m.daily[.dose]?.notice == RemindersCopy.medicationMissing)
        #expect(c.pending.isEmpty)
        await m.setMedication(MedicationEntry(name: "Concerta", dose: "36 mg"))   // no time yet
        await m.setEnabled(.dose, true)
        #expect(m.daily[.dose]?.enabled == false)
        #expect(c.pending.isEmpty)
    }

    @Test func settingTheMedicationTimeMovesAnEnabledReminder() async throws {
        let (m, c, store) = try makeSafety()
        await m.load()
        await m.setMedication(MedicationEntry(name: "Concerta", dose: "36 mg", usualTime: ReminderTime(hour: 7, minute: 45)))
        await m.setEnabled(.dose, true)
        #expect(m.daily[.dose]?.scheduled == ReminderTime(hour: 7, minute: 45))
        await m.setMedication(MedicationEntry(name: "Concerta", dose: "36 mg", usualTime: ReminderTime(hour: 9, minute: 0)))
        let r = try #require(c.pending.first { $0.identifier == ReminderKind.dose.identifier })
        #expect((r.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour == 9)
        #expect(r.content.title == "Medication · Concerta")
        #expect(MedicationStore(prefs: store).load()?.usualTime == ReminderTime(hour: 9, minute: 0))
    }

    @Test func clearingTheMedicationSwitchesItsReminderOff() async throws {
        let (m, c, store) = try makeSafety()
        await m.load()
        await m.setMedication(MedicationEntry(name: "Concerta", usualTime: ReminderTime(hour: 7, minute: 45)))
        await m.setEnabled(.dose, true)
        await m.setMedication(nil)
        #expect(m.daily[.dose]?.enabled == false)
        #expect(!c.pending.contains { $0.identifier == ReminderKind.dose.identifier })
        #expect(MedicationStore(prefs: store).load() == nil)
    }

    @Test func safetyToggleSchedulesFromTheStoredConfirmation() async throws {
        let (m, _, store) = try makeSafety()
        try GateSettingsStore(prefs: store).save(GateSettings(hrCapBpm: 170, hrCapConfirmedOn: "2026-09-01"))
        await m.load()
        #expect(m.hrCapBpm == 170)
        #expect(m.hrCapCheckDue == nil)
        await m.setHrCapCheckEnabled(true)
        #expect(m.hrCapCheckDue == "2026-10-27")
        #expect(m.hrCapCheckLine == "Confirm your HR cap (170) every 8 weeks · next 2026-10-27")
        await m.setHrCapCheckEnabled(false)
        #expect(m.hrCapCheckDue == nil)
        #expect(m.hrCapCheckLine == "Confirm your HR cap (170) every 8 weeks · off")
    }

    /// Toby 2026-09-24: no cap ⇒ the 8-week re-check is off and cannot be switched on.
    @Test func noCapTurnsTheRecheckOff() async throws {
        let (m, c, store) = try makeSafety()
        let s = ReminderScheduler(center: c)
        _ = try await s.scheduleHrCapCheck(confirmedOn: "2026-09-01", capBpm: 170, today: "2026-09-24")   // left from an old cap
        try GateSettingsStore(prefs: store).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-24"))
        await m.load()
        #expect(m.hrCapBpm == nil)
        #expect(m.hrCapCheckDue == nil)                         // load() cancels the stale one
        await m.setHrCapCheckEnabled(true)
        #expect(m.hrCapCheckDue == nil)
        #expect(await s.hrCapCheckDue() == nil)
        #expect(m.hrCapCheckLine == RemindersCopy.noCapLine)
        #expect(RemindersCopy.noCapLine == "No heart-rate limit set · off")
    }

    @Test func hrCapCheckKeepsItsOwnPermissionNotice() async throws {
        let store = try PrefStore(db: AppDatabase.inMemory())
        let c = FakeNotificationCenter(status: .notDetermined); c.grantOnRequest = false
        let m = RemindersViewModel(scheduler: ReminderScheduler(center: c), prefs: store, today: { "2026-09-24" })
        try GateSettingsStore(prefs: store).save(GateSettings(hrCapBpm: 170, hrCapConfirmedOn: "2026-09-01"))
        await m.load()
        await m.setHrCapCheckEnabled(true)
        #expect(m.hrCapCheckDue == nil)
        #expect(c.pending.isEmpty)
    }
}
