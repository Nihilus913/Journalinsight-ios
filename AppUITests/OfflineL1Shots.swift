import XCTest

/// W-OFFLINE OFF-1 sim proof: launched with NO hub config (empty Keychain, no `-hub-url`), the
/// connection sheet is cancelled and Today, Training, Nutrition, Energy and Goals are shot — none
/// blank, the hub screens on their `.needsHub` line. `UITEST_SHOTS` = the proof PNG dir.
final class OfflineL1Shots: JIUITestCase {
    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
    }

    private func more(_ id: String, shot name: String, expect text: String?) {
        tab("More")
        let row = el(id)
        guard row.waitForExistence(timeout: 15) else { dump(id); return }
        row.tap()
        sleep(3)
        shot(name)
        if let text {
            let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 10), "\(name): no '\(text)'")
        }
        back()
    }

    func testNoHubTabs() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-no-healthkit", "-no-onboarding", "-no-push", "-ui-testing"]
        app.launch()
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 10) { cancel.tap() }
        sleep(3)
        shot("off1-today")
        tab("Training")
        sleep(3)
        shot("off1-training")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Connect the hub in Settings")).firstMatch
            .waitForExistence(timeout: 10), "Training: no needs-hub line")
        more("more.nutrition", shot: "off1-nutrition", expect: "Connect the hub in Settings")
        more("more.energy", shot: "off1-energy", expect: "Connect the hub in Settings")
        more("more.goals", shot: "off1-goals", expect: nil)
    }
}
