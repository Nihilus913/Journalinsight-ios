import XCTest

/// W-UITEST UT-2 (F10-2): the owed B-40 V5–V8 tap proofs, re-runnable. Each test leaves its proof
/// screenshot (`V5-…` … `V8-…`). Data: the fixture hub's plan (Sunday = Rest, `s7`) and library
/// ("Zone 2 40 min", "Norwegian 4×4", the seeded segments-only "UITest Segments Tempo").
final class TrainingProofTests: JIUITestCase {
    static let segmentsOnly = "UITest Segments Tempo"

    override func setUpWithError() throws {
        try super.setUpWithError()
        launch()
        passGate()
        tab("Training")
        XCTAssertTrue(el("training-hero").waitForExistence(timeout: 20))
    }

    private func openDay(_ weekday: Int) {
        tapId("training-week-day-\(weekday)")
        XCTAssertTrue(el("training-day-sheet").waitForExistence(timeout: 10), "day sheet \(weekday) did not open")
    }

    /// W-PLANNER PL-5: the library is the Planner's ALL WORKOUTS (toolbar icon → Planner).
    private func openLibrary() {
        tapId("training-open-planner")
        XCTAssertTrue(el("workouts-list").waitForExistence(timeout: 15), "Planner did not open")
    }

    /// B40-V5: change a day in the day sheet → the hero follows without a relaunch.
    /// The verify-r2 repro: Tuesday's plan session "Interval Run" (s5) becomes the plan's
    /// "Long Zone 2" (s6); the hero must say Long Zone 2, not the old session or "— No data".
    func testV5_changeDayHeroFollows() {
        openDay(1)
        tapId("training-day-change-s5")
        tapId("training-day-option-s6")
        reveal(el("training-day-entry-s6"), "day sheet entry Long Zone 2")
        tapId("training-day-done")
        XCTAssertTrue(el("training-day-sheet").waitForNonExistence(timeout: 10))
        let follows = hero(labelContains: "Long Zone 2")
        if !follows.waitForExistence(timeout: 15) { dump("V5-hero") }
        XCTAssertTrue(follows.exists, "the hero did not follow the change to Long Zone 2")
        XCTAssertFalse(hero(labelContains: "Interval Run").exists, "the hero still shows Interval Run")
        shot("V5-hero-follows-day-change")
    }

    /// B40-V6: Send to Watch shows minutes + steps for a segments-only template (compat `steps: []`).
    func testV6_sendToWatchSegmentsOnlySummary() {
        tap(hero(labelContains: "Send to Watch"), "hero Send to Watch")
        let row = element(idPrefix: "send-to-watch-template-", labelContains: Self.segmentsOnly)
        reveal(row, "Send to Watch row \(Self.segmentsOnly)", timeout: 20)
        XCTAssertTrue(row.label.contains("40 min · 2 steps"), "summary line: \(row.label)")
        shot("V6-send-to-watch-segments-only")
    }

    /// B40-V7: the library row's menu "Send to Watch" opens the sheet with that workout picked.
    func testV7_librarySendToWatch() {
        openLibrary()
        let row = element(idPrefix: "workouts-row-", labelContains: Self.segmentsOnly)
        reveal(row, "library row \(Self.segmentsOnly)")
        let id = row.identifier.replacingOccurrences(of: "workouts-row-", with: "")
        row.press(forDuration: 1.2)   // the row's context menu carries Send to Watch
        tap(app.buttons["Send to Watch"].firstMatch, "menu Send to Watch")
        let picked = el("send-to-watch-template-\(id)")
        reveal(picked, "Send to Watch sheet on \(Self.segmentsOnly)", timeout: 20)
        XCTAssertEqual(picked.value as? String, "Selected")
        XCTAssertTrue(el("send-to-watch-send").exists)
        shot("V7-library-send-to-watch")
    }

    /// B40-V8: the red Delete swipe asks on a confirmation anchored at that row, then deletes.
    func testV8_redDeleteAnchoredConfirm() throws {
        let name = "Norwegian 4×4"
        openLibrary()
        let row = element(idPrefix: "workouts-row-", labelContains: name)
        reveal(row, "library row \(name)")
        let rowY = row.frame.midY
        // W-PLANNER: the Planner's rows carry Delete in their context menu (no List swipe there).
        row.press(forDuration: 1.2)
        let swipeDelete = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5), "no Delete in the menu of \(name)")
        shot("V8-red-delete-menu-open")
        swipeDelete.tap()
        let title = app.staticTexts["Delete \(name)?"]
        if !title.waitForExistence(timeout: 10) { dump("V8-confirm") }
        XCTAssertTrue(title.exists, "no confirmation for \(name)")
        // Anchored: the confirmation sits by the row, not as a bottom sheet across the screen.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).allElementsBoundByIndex.last!
        XCTAssertLessThan(abs(confirm.frame.midY - rowY), 320, "confirmation at y=\(confirm.frame.midY), row at y=\(rowY)")
        shot("V8-red-delete-anchored-confirm")
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 15), "\(name) still listed after Delete")
        let templates = try hubGet("/api/v1/planning/workout-templates") as? [[String: Any]] ?? []
        XCTAssertFalse(templates.contains { $0["name"] as? String == name }, "the hub still has \(name)")
    }
}
