import XCTest

/// W-UITEST UT-1 (B-60): the base of every committed UI test. Real taps on "iPhone 18 Pro" against
/// the throwaway fixture hub (`AppUITests/fixture-hub.sh test` starts it and passes its URL/token as
/// `TEST_RUNNER_UITEST_HUB_URL` / `TEST_RUNNER_UITEST_HUB_TOKEN`).
///
/// Every launch carries `-JIForceGate YES` (Decide always opens first, so every test starts from
/// the same screen) and the DEBUG `-hub-url/-hub-token` connection — never the prod hub.
class JIUITestCase: XCTestCase {
    var app: XCUIApplication!

    var hubURL: String { ProcessInfo.processInfo.environment["UITEST_HUB_URL"] ?? "http://127.0.0.1:8150" }
    var hubToken: String { ProcessInfo.processInfo.environment["UITEST_HUB_TOKEN"] ?? "uitest-fixture-token" }
    /// Optional host directory for the proof PNGs (`docs/waves/reports/W-UITEST/`); the shots are
    /// always attached to the .xcresult too.
    var shotsDir: String? { ProcessInfo.processInfo.environment["UITEST_SHOTS"].flatMap { $0.isEmpty ? nil : $0 } }

    /// The launch arguments every test uses (UT-1).
    static func launchArguments(hubURL: String, hubToken: String) -> [String] {
        ["-JIForceGate", "YES", "-hub-url", hubURL, "-hub-token", hubToken,
         "-no-healthkit", "-no-onboarding", "-no-push", "-ui-testing"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCTAssertFalse(hubURL.hasSuffix(":8000"), "UI tests never talk to the prod hub")
    }

    func launch() {
        app = XCUIApplication()
        app.launchArguments = Self.launchArguments(hubURL: hubURL, hubToken: hubToken)
        app.launch()
    }

    /// Decide is forced open: answer it with Go (a verdict-override "accept" write, never a gate
    /// respond), then wait until it is gone.
    func passGate() {
        let go = app.buttons["today.decide.go"]
        XCTAssertTrue(go.waitForExistence(timeout: 30), "-JIForceGate YES did not open Decide")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: go)
        waitForExpectations(timeout: 30)
        go.tap()
        XCTAssertTrue(go.waitForNonExistence(timeout: 15), "Decide stayed up after Go")
    }

    func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 15), "no \(name) tab")
        b.tap()
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func element(idPrefix: String, labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", idPrefix, text)).firstMatch
    }

    /// Waits for `e`, scrolling up a little at a time while it is missing or not hittable.
    func reveal(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        _ = e.waitForExistence(timeout: timeout)
        var n = 0
        while !(e.exists && e.isHittable) && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        XCTAssertTrue(e.exists, "missing \(what)", file: file, line: line)
    }

    func tap(_ e: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(e, what, file: file, line: line)
        e.tap()
    }

    func tapId(_ id: String, file: StaticString = #filePath, line: UInt = #line) { tap(el(id), id, file: file, line: line) }

    /// The proof screenshot: attached to the result bundle and, with `UITEST_SHOTS`, written as
    /// `<dir>/<name>.png`.
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let shotsDir {
            try? FileManager.default.createDirectory(atPath: shotsDir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: shotsDir).appendingPathComponent("\(name).png"))
        }
    }

    /// A read of the fixture hub (GET only) — what the app wrote, checked at the source.
    func hubGet(_ path: String) throws -> Any {
        var req = URLRequest(url: URL(string: hubURL + path)!)
        req.setValue("Bearer \(hubToken)", forHTTPHeaderField: "Authorization")
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = expectation(description: "GET \(path)")
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 { result = .failure(URLError(.badServerResponse)) }
            else { result = .success(data ?? Data()) }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try JSONSerialization.jsonObject(with: try result.get())
    }
}

/// UT-1: the target runs — the forced gate opens on launch against the fixture hub, Go clears it.
final class LaunchSmokeTests: JIUITestCase {
    func testForcedGateOpensAndGoClearsIt() {
        launch()
        passGate()
        tab("Training")
        XCTAssertTrue(el("training-hero").waitForExistence(timeout: 20), "Training did not load from the fixture hub")
    }
}
