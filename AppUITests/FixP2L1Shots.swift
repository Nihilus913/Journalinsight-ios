import XCTest

/// W-FIX-P2 lane l1 proof shots (fixture hub, on-device verdict with 2 fake Apple nights):
/// RG-16 the Decide HRV row names the phone baseline; RG-53 Settings › Developer copy.
final class FixP2L1Shots: JIUITestCase {
    private func launchOnDevice() {
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding",
                               "-no-push", "-ui-testing", "-ji.ondevice.verdict.enabled", "YES",
                               "-ji.ondevice.fakeNights", "2", "-ji.ondevice.overlayFrom", "2026-10-05"]
        app.launch()
    }

    func testRG16_decideHrvRowNamesThePhoneBaseline() {
        launchOnDevice()
        _ = app.wait(for: .runningForeground, timeout: 20)
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'phone baseline'")).firstMatch
        reveal(row, "HRV row with 'phone baseline'", timeout: 30)
        // The on-device compute asks for Health access once (sim): decline it, then re-find the row.
        let deny = app.buttons["Don’t Allow"].exists ? app.buttons["Don’t Allow"] : app.buttons["Don't Allow"]
        if deny.waitForExistence(timeout: 5) { deny.tap(); sleep(2) }
        reveal(row, "HRV row after the Health sheet", timeout: 10)
        shot("rg16-decide-hrv-phone-baseline")
        XCTAssertTrue(row.label.contains("phone baseline 2/28"), "row: \(row.label)")
    }

    func testRG53_developerCopy() {
        launchOnDevice()
        tapId("root.settings")
        let dev = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Developer'")).firstMatch
        tap(dev, "Developer group")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'computed on this iPhone. The'")).firstMatch
        reveal(note, "gate note")
        shot("rg53-settings-developer")
        XCTAssertTrue(note.label.contains("oracle"), "note: \(note.label)")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Shadow run'")).firstMatch.exists)
    }
}
