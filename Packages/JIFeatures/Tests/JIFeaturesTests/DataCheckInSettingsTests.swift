import Foundation
import Testing
import UserNotifications
import JICore
import JIPersistence
@testable import JIFeatures

// W-B102 C-6 — the Reminders toggle writes the shared pref and cancels a pending prompt.

@MainActor
struct DataCheckInSettingsTests {
    @Test func toggleOffCancelsAndPersists() async throws {
        let center = FakeNotificationCenter()
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let prompt = CheckInPrompt(rule: .amber2, day: DayKey(iso: "2026-10-04")!, title: "t", body: "b", why: "w", morningsLine: nil)
        try await center.add(CheckInNotification.request(prompt: prompt, at: ReminderTime(hour: 9, minute: 0)))
        let model = RemindersViewModel(scheduler: ReminderScheduler(center: center), prefs: prefs)
        await model.load()
        #expect(model.dataCheckInEnabled)   // default on
        model.setDataCheckInEnabled(false)
        #expect(try prefs.get(CheckInPromptModel.enabledKey, as: Bool.self) == false)
        #expect(!center.pending.contains { $0.identifier == CheckInNotification.identifier })
        #expect(!CheckInPromptModel(center: center, prefs: prefs).enabled)   // the Today model reads the same pref
        model.setDataCheckInEnabled(true)
        #expect(try prefs.get(CheckInPromptModel.enabledKey, as: Bool.self) == true)
        let reloaded = RemindersViewModel(scheduler: ReminderScheduler(center: center), prefs: prefs)
        await reloaded.load()
        #expect(reloaded.dataCheckInEnabled)
    }

    @Test func rulesListedInSettings() {
        #expect(CheckInRule.allCases.map(\.title) == ["Two amber mornings", "Override without a reason", "3 days without a check-in"])
    }
}
