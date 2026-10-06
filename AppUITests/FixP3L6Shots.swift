import XCTest

/// W-FIX-P3 lane l6 proof shots (lane hub on a prod clone, no HealthKit). The runner script
/// stops / starts the hub between the methods (an XCUITest cannot):
///   1. testA_recoveryColdCacheOffline — fresh install, hub DOWN: Recovery says no "0 nights" (RG-69)
///   2. testB_warmOnline — hub UP: Time in zone M + Progress (warm the read cache), Nutrition today,
///      Mon 5 Oct (a past 2-meal day) and the method sheet (RG-83)
///   3. testC_cachedOffline — hub DOWN: Time in zone + Progress say "Offline — showing data from" (RG-69)
final class FixP3L6Shots: JIUITestCase {
    private func launchPlain() {
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding",
                               "-no-push", "-ui-testing"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(3)
        // Decide may come up (cached verdict offline): answer Go so the tabs are reachable.
        let go = app.buttons["today.decide.go"]
        if go.waitForExistence(timeout: 5), go.isEnabled { go.tap(); _ = go.waitForNonExistence(timeout: 10) }
        clearSheets()
    }

    /// HealthKit's own "Health Access" sheet can come up over any screen on the sim: decline it.
    private func clearSheets() {
        sleep(1)
        _ = declineHealthAccessSheet()
        let skip = app.buttons["Skip for now"]
        if skip.exists && skip.isHittable { skip.tap(); sleep(1) }
    }

    private func contains(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openZoneTime() {
        clearSheets()
        tab("Training")
        tapId("training-zone-time")
        sleep(2)
        let m = app.segmentedControls["zone-time-range"].buttons["M"]
        if m.waitForExistence(timeout: 10) { m.tap() }
        sleep(3)
    }

    private func openProgress() {
        clearSheets()
        tab("Training")
        tapId("training-progress")
        sleep(4)
    }

    func testA_recoveryColdCacheOffline() {
        launchPlain()
        tab("Recovery")
        sleep(4)
        shot("rg69-recovery-cold-cache-offline")
        XCTAssertFalse(contains("0 nights").exists, "Recovery cold cache still says '0 nights'")
    }

    func testB_warmOnline() {
        launchPlain()
        openZoneTime()
        shot("rg69-zone-time-M-online")
        XCTAssertFalse(el("zone-time-offline").exists, "online zone time shows the offline line")
        app.navigationBars.buttons.firstMatch.tap()
        openProgress()
        shot("rg69-progress-online")
        app.navigationBars.buttons.firstMatch.tap()

        clearSheets()
        tab("More")
        tapId("more.nutrition")
        sleep(4)
        let note = el("nutrition-readonly-note")
        reveal(note, "Nutrition read-only note (today)", timeout: 20)
        shot("rg83-nutrition-today")
        XCTAssertTrue(note.label.contains("Meals come from YAZIO"), "today note: \(note.label)")
        // A past, partly logged day: Mon 5 Oct (2 meals) — the strip holds the last 7 days only.
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        clearSheets()
        let past = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'nutrition-week-strip' AND label BEGINSWITH 'Monday 5'")).firstMatch
        tap(past, "strip day Monday 5")
        sleep(3)
        let dq = el("diet-quality-card")
        reveal(dq, "Diet quality card (5 Oct)", timeout: 20)
        shot("rg83-nutrition-5-oct-diet-quality")
        XCTAssertFalse(contains("so far").exists, "5 Oct still says 'so far'")
        let note29 = el("nutrition-readonly-note")
        reveal(note29, "Nutrition read-only note (5 Oct)", timeout: 10)
        XCTAssertTrue(note29.label.contains("Meals come from YAZIO"), "5 Oct note: \(note29.label)")
        shot("rg83-nutrition-5-oct-note")
        let how = el("diet-quality-how")
        var n = 0
        while !(how.exists && how.isHittable) && n < 8 { app.swipeDown(velocity: .slow); n += 1 }
        tap(how, "How it is calculated")
        let sheet = el("diet-quality-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "method sheet did not open")
        sleep(1)
        shot("rg83-diet-quality-method-sheet")
    }

    func testC_cachedOffline() {
        launchPlain()
        openZoneTime()
        let zoneOffline = el("zone-time-offline")
        XCTAssertTrue(zoneOffline.waitForExistence(timeout: 15), "zone time: no offline line")
        shot("rg69-zone-time-M-offline")
        XCTAssertTrue(zoneOffline.label.hasPrefix("Offline — showing data from"), "zone: \(zoneOffline.label)")
        app.navigationBars.buttons.firstMatch.tap()
        openProgress()
        let progOffline = el("progress.offline")
        XCTAssertTrue(progOffline.waitForExistence(timeout: 15), "progress: no offline line")
        shot("rg69-progress-offline")
        XCTAssertTrue(progOffline.label.hasPrefix("Offline — showing data from"), "progress: \(progOffline.label)")
    }
}
