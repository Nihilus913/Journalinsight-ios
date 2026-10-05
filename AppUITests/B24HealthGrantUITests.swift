import XCTest

/// B-24 P3 sim setup: grants State of Mind WRITE once through the real UI path — Settings ›
/// Apple Health › "Mirror mood to Apple Health" toggle -> HealthKit's Health Access sheet ->
/// turn on all -> Allow. Simulators have no `simctl privacy` service for Health, so this is the
/// one tap the proof needs; `AppTests/MoodMirrorSimTests` then runs against the granted store.
/// Opt-in: `TEST_RUNNER_JI_B24_GRANT=1 xcodebuild test -scheme AppUITests ... -only-testing:AppUITests/B24HealthGrantUITests`.
final class B24HealthGrantUITests: JIUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JI_B24_GRANT"] == "1", "opt-in (JI_B24_GRANT=1)")
    }

    private func label(_ labels: [String], prefix: Bool = false) -> XCUIElement {
        let pred = prefix
            ? NSPredicate(format: "label BEGINSWITH 'Select All' OR label BEGINSWITH 'Turn On All'")
            : NSPredicate(format: "label IN %@", labels)
        return app.descendants(matching: .any).matching(pred).firstMatch
    }

    /// Health Access sheet: turn every topic on, then Allow. False when no sheet showed.
    private func allowHealthSheet(timeout: TimeInterval) -> Bool {
        let all = label([], prefix: true)
        guard all.waitForExistence(timeout: timeout) else { return false }
        all.tap()
        let allow = app.buttons.matching(NSPredicate(format: "label == 'Allow'")).firstMatch
        var n = 0
        while !(allow.exists && allow.isEnabled && allow.isHittable) && n < 12 { app.swipeUp(); n += 1 }
        guard allow.exists else { dump("Health Access sheet (no Allow)"); return false }
        allow.tap()
        return all.waitForNonExistence(timeout: 10)
    }

    func testGrantStateOfMindWriteViaSettingsToggle() {
        launch()
        passGate()
        let settings = app.buttons["Settings"].firstMatch
        if !settings.waitForExistence(timeout: 10) { tab("Today") }
        tap(app.buttons["Settings"].firstMatch, "Settings toolbar button")
        tapId("settings.root.health")
        shot("b24-settings-health-screen")
        // The section stamps its own id over the Toggle's, so find the row by its label.
        let row = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Mirror mood to Apple Health'")).firstMatch
        reveal(row, "mood mirror toggle")
        let toggle = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        shot("b24-settings-health-before")
        let wasOn = (toggle.value as? String) == "1"
        if wasOn { toggle.tap() }  // already granted on this sim: off, then on again below
        toggle.tap()
        let sheet = allowHealthSheet(timeout: 15)
        shot("b24-settings-health-after")
        print("[B24-GRANT] sheet=\(sheet) toggle=\(toggle.value ?? "nil")")
        XCTAssertTrue(sheet || wasOn, "no Health Access sheet appeared on toggle-on")
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
    }
}
