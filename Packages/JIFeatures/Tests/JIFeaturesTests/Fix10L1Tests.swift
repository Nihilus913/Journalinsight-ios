import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX10 F10-3 — the three W-B40 verify observations (docs/waves/reports/W-B40-verify.md obs 1–3).

private func runTemplate(_ name: String) -> WorkoutTemplate {
    WorkoutTemplate(templateId: 7, name: name, activity: "running", location: .outdoor, weekdays: [1], steps: [],
                    updatedAt: "2026-09-28T08:00:00Z",
                    segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 1800), target: .hrRange(lo: 116, hi: 138)))])])
}

/// obs 1: the editor's Save is enabled on an edit with no changes.
@MainActor @Test func f103EditorSaveWaitsForAChange() async {
    var sent = 0
    let vm = WorkoutEditorViewModel(template: runTemplate("Zone 2 40 min")) { _ in sent += 1; return .saved }
    #expect(!vm.hasChanges)
    #expect(!vm.canSave)
    vm.name = "Zone 2 45 min"
    #expect(vm.hasChanges && vm.canSave)
    vm.name = "Zone 2 40 min"                  // back to what was stored
    #expect(!vm.hasChanges && !vm.canSave)
    vm.descriptionText = "Easy"
    #expect(vm.canSave)
    #expect(await vm.save())
    #expect(sent == 1)
}

/// An unchanged edit closes without a hub write (nothing to save is not an error).
@MainActor @Test func f103UnchangedSaveClosesWithoutAWrite() async {
    var sent = 0
    let vm = WorkoutEditorViewModel(template: runTemplate("Zone 2 40 min")) { _ in sent += 1; return .saved }
    #expect(await vm.save())
    #expect(sent == 0)
    #expect(vm.errorText == nil)
}

/// A new workout is always a change (Save waits only for a valid draft).
@MainActor @Test func f103NewWorkoutIsAChange() {
    let vm = WorkoutEditorViewModel(template: nil) { _ in .saved }
    #expect(vm.hasChanges)
    vm.name = "Easy"
    #expect(vm.canSave)
}

/// obs 2: offline, the Import row is disabled and says why — its icon goes muted too (CTA blue
/// when it can run; green is reserved for verdicts, rule 6).
@Test func f103ImportIconFollowsItsDisabledState() {
    #expect(workoutsImportRole(disabled: true) == .muted)
    #expect(workoutsImportRole(disabled: false) == .info)
}

#if canImport(WorkoutKit)
/// obs 3: Bevel is retired (W-B38 / B-40) — the Send to Watch footer no longer names it.
@Test func f103SendToWatchFooterNoLongerNamesBevel() {
    let note = sendToWatchAlertNote(.none)
    #expect(!note.contains("Bevel"))
    #expect(note == "Cardio only — strength parts are logged in JournalInsight, not sent. Heart-rate alerts are absolute bpm.")
}
#endif

/// F10-2: the launch routes the screenshot proofs use (developer mode off — no taps).
@Test func f102LaunchRoutesParse() {
    #expect(trainingLaunchSendToWatch(["app"]) == nil)
    #expect(trainingLaunchSendToWatch(["app", "-send-to-watch-open"]) == .hero)
    #expect(trainingLaunchSendToWatch(["app", "-send-to-watch-open", "t12"]) == .template(12))
    #expect(trainingLaunchSendToWatch(["app", "-send-to-watch-open", "-no-push"]) == .hero)
    #expect(trainingLaunchDaySheetOpens(["app", "-training-day", "1"]))
    #expect(!trainingLaunchDaySheetOpens(["app", "-training-day-sheet", "off"]))
}
