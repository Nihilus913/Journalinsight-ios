import Foundation
import Testing
import UserNotifications
import JICore
import JIPersistence
@testable import JIFeatures

// W-B102 C-3 — the model that evaluates, schedules once a day, cancels and snoozes.

private func d(_ iso: String) -> DayKey { DayKey(iso: iso)! }

private let amberWeek: [CheckInMorning] = (0..<7).map { i in
    CheckInMorning(day: d("2026-10-04").adding(days: -i), verdict: i < 2 ? "MODIFIED — easy Z2" : "GO (auto-regulated) — Z2")
}
private let goWeek: [CheckInMorning] = (0..<7).map { CheckInMorning(day: d("2026-10-04").adding(days: -$0), verdict: "GO — Z2") }
private let morning = DateComponents(hour: 7, minute: 41)

@MainActor
private func make() throws -> (CheckInPromptModel, FakeNotificationCenter, PrefStore) {
    let center = FakeNotificationCenter()
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    return (CheckInPromptModel(center: center, prefs: prefs), center, prefs)
}

@MainActor
struct CheckInPromptModelTests {
    @Test func promptSchedulesOnePendingRequest() async throws {
        let (model, center, _) = try make()
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: morning)
        #expect(model.livePrompt?.rule == .amber2)
        #expect(center.pending.map(\.identifier) == [CheckInNotification.identifier])
        let t = try #require(center.pending.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(t.dateComponents.hour == 9 && t.dateComponents.minute == 0)
    }

    @Test func onceADay() async throws {
        let (model, center, _) = try make()
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: morning)
        center.pending.removeAll()   // delivered / swiped away
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: DateComponents(hour: 12, minute: 0))
        #expect(center.pending.isEmpty)
        #expect(model.livePrompt?.rule == .amber2)   // the Today card stays while the rule holds
        // the next day may ask again
        let next = amberWeek.map { CheckInMorning(day: $0.day.adding(days: 1), verdict: $0.verdict) }
        await model.refresh(CheckInInputs(today: d("2026-10-05"), mornings: next), now: morning)
        #expect(center.pending.count == 1)
    }

    @Test func quietCancelsPending() async throws {
        let (model, center, _) = try make()
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: morning)
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: goWeek), now: morning)
        #expect(model.livePrompt == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func snoozeHidesAndCancels() async throws {
        let (model, center, _) = try make()
        let inputs = CheckInInputs(today: d("2026-10-04"), mornings: amberWeek)
        await model.refresh(inputs, now: morning)
        model.snoozeToday(d("2026-10-04"))
        #expect(model.livePrompt == nil)
        #expect(center.pending.isEmpty)
        await model.refresh(inputs, now: morning)   // a later refresh the same day stays quiet
        #expect(model.livePrompt == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func disabledIsOffAndCancels() async throws {
        let (model, center, prefs) = try make()
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: morning)
        model.setEnabled(false)
        #expect(try prefs.get(CheckInPromptModel.enabledKey, as: Bool.self) == false)
        #expect(center.pending.isEmpty)
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: morning)
        #expect(model.evaluation == .off)
        #expect(center.pending.isEmpty)
        model.setEnabled(true)
        #expect(model.enabled)
    }

    @Test func lateEveningShowsCardButNoNotification() async throws {
        let (model, center, _) = try make()
        await model.refresh(CheckInInputs(today: d("2026-10-04"), mornings: amberWeek), now: DateComponents(hour: 22, minute: 30))
        #expect(model.livePrompt?.rule == .amber2)
        #expect(center.pending.isEmpty)
    }

    @Test func historyLoaderReadsSevenDaysAndSkipsMissing() async {
        let mornings = await CheckInPromptModel.loadMornings(today: d("2026-10-04")) { date in
            if date == "2026-10-01" { throw URLError(.fileDoesNotExist) }   // 404 → absent
            return date == "2026-10-04" ? "REST day" : "GO — Z2"
        }
        #expect(mornings.count == 6)
        #expect(mornings.first { $0.day == d("2026-10-04") }?.verdict == "REST day")
        #expect(!mornings.contains { $0.day == d("2026-10-01") })
    }

    @Test func latestCheckinDayReadsTheStore() async throws {
        let db = try AppDatabase.inMemory()
        let store = CheckInStore(db: db)
        #expect(try store.latestDate() == nil)
        try store.upsertToday(NewCheckIn(date: "2026-10-01", mood: nil, stress: 2, energy: 3, dosed: false,
                                         irritability: nil, restlessness: nil, appetite: nil, note: nil))
        try store.upsertToday(NewCheckIn(date: "2026-09-29", mood: nil, stress: 2, energy: 3, dosed: false,
                                         irritability: nil, restlessness: nil, appetite: nil, note: nil))
        #expect(try store.latestDate() == "2026-10-01")
    }
}
