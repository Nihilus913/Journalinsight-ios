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

    private func openLibrary() {
        tapId("training-open-library")
        XCTAssertTrue(el("workouts-list").waitForExistence(timeout: 15), "library did not open")
    }

    /// B40-V5: change a day in the day sheet → the hero follows without a relaunch.
    func testV5_changeDayHeroFollows() {
        openDay(6)
        tapId("training-day-change-s7")
        tap(element(idPrefix: "training-day-option-", labelContains: "Zone 2 40 min"), "option Zone 2 40 min")
        XCTAssertTrue(element(idPrefix: "training-day-entry-", labelContains: "Zone 2 40 min").waitForExistence(timeout: 15),
                      "the day sheet never showed the new session")
        tapId("training-day-done")
        XCTAssertTrue(el("training-day-sheet").waitForNonExistence(timeout: 10))
        let title = el("training-session-title")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Zone 2 40 min"), evaluatedWith: title)
        waitForExpectations(timeout: 15)
        shot("V5-hero-follows-day-change")
    }

    /// B40-V6: Send to Watch shows minutes + steps for a segments-only template (compat `steps: []`).
    func testV6_sendToWatchSegmentsOnlySummary() {
        tapId("training-send-to-watch")
        let row = element(idPrefix: "send-to-watch-template-", labelContains: Self.segmentsOnly)
        reveal(row, "Send to Watch row \(Self.segmentsOnly)", timeout: 20)
        XCTAssertTrue(row.label.contains("40 min · 2 steps"), "summary line: \(row.label)")
        shot("V6-send-to-watch-segments-only")
    }

    /// B40-V7: the library row's swipe "Send to Watch" opens the sheet with that workout picked.
    func testV7_librarySendToWatch() {
        openLibrary()
        let row = element(idPrefix: "workouts-row-", labelContains: Self.segmentsOnly)
        reveal(row, "library row \(Self.segmentsOnly)")
        let id = row.identifier.replacingOccurrences(of: "workouts-row-", with: "")
        row.swipeLeft()
        tap(app.buttons["Send to Watch"].firstMatch, "swipe Send to Watch")
        let picked = el("send-to-watch-template-\(id)")
        XCTAssertTrue(picked.waitForExistence(timeout: 20), "the Send to Watch sheet did not open on \(Self.segmentsOnly)")
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
        row.swipeLeft()
        tap(app.buttons["Delete"].firstMatch, "swipe Delete")
        XCTAssertTrue(app.staticTexts["Delete \(name)?"].waitForExistence(timeout: 10), "no confirmation for \(name)")
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
