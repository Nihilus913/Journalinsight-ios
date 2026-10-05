import XCTest

/// W-FIX-P0 RG-01 (B-117) sim proof: Training › Planner › Day 1 › Log sets · the first lift at
/// 50 kg × 12 · 'Log set' ×3 → three set rows on screen and the rest countdown running (the
/// session start no longer dies with SQLITE_BUSY on a second pool).
/// `bash AppUITests/fixture-hub.sh test -only-testing:AppUITests/B117StrengthLogShots`
final class B117StrengthLogShots: JIUITestCase {
    func testLogThreeSetsOnTheSharedPool() {
        launch()
        passGate()
        tab("Training")
        XCTAssertTrue(el("training-hero").waitForExistence(timeout: 20))
        addUIInterruptionMonitor(withDescription: "notification permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }

        tapId("training-open-planner")
        XCTAssertTrue(el("workouts-list").waitForExistence(timeout: 15), "Planner did not open")
        let post073 = element(idPrefix: "workouts-row-", labelContains: "Day 1")
        let day1 = post073.waitForExistence(timeout: 10) ? post073 : element(idPrefix: "planner-row-s", labelContains: "Day 1")
        tap(day1, "Planner row Day 1")
        XCTAssertTrue(el("planner-strength-detail").waitForExistence(timeout: 10), "Day 1 detail did not open")
        tap(el("planner-log-sets"), "Log sets")
        reveal(el("strength-log-add-exercise"), "the set logger after Log sets")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        // The first lift of the logger (Bench on the fixture plan when it is Day 1's first).
        let logSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'strength-log-set-'")).firstMatch
        reveal(logSet, "a Log set button")
        let key = String(logSet.identifier.dropFirst("strength-log-set-".count))

        let weight = el("strength-weight-\(key)")
        if weight.waitForExistence(timeout: 5) {
            weight.tap()
            let current = (weight.value as? String) ?? ""
            weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(current.count, 6)) + "50")
        }
        let reps = app.steppers["strength-reps-\(key)"].firstMatch
        if reps.waitForExistence(timeout: 5) {
            var n = 0
            while n < 30, let v = reps.value as? String, let r = Int(v.split(separator: " ").first ?? ""), r != 12 {
                reps.buttons[r < 12 ? "Increment" : "Decrement"].tap(); n += 1
            }
            if (reps.value as? String)?.hasPrefix("not set") == true {
                for _ in 0..<12 { reps.buttons["Increment"].tap() }
            }
        }
        // Put the keyboard away so the set rows and the rest countdown are on screen.
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Target'")).firstMatch.tap()
        XCTAssertFalse(el("strength-set-\(key)-1").exists, "a set was already logged (stale install)")
        shot("B117-0-before")

        for i in 1...3 {
            tap(logSet, "Log set \(i)")
            XCTAssertTrue(el("strength-set-\(key)-\(i)").waitForExistence(timeout: 10), "set \(i) not shown")
        }
        let couldNot = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Could not'")).firstMatch
        XCTAssertFalse(couldNot.exists, "an error is shown")
        XCTAssertTrue(el("strength-rest-timer").waitForExistence(timeout: 10), "rest countdown did not start")
        XCTAssertFalse(el("strength-set-\(key)-4").exists, "more than three sets")
        el("strength-set-\(key)-1").swipeDown(velocity: .slow)
        shot("B117-1-three-sets-rest-running")
    }
}
