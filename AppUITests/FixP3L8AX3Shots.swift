import XCTest

/// W-FIX-P3 RG-21: at AX3 (sim content size accessibility-extra-large) no element on Today's
/// Decide scroll may sit outside the screen. Pages down the scroll, shooting each page and
/// listing every element whose frame leaves the screen horizontally (the bisect).
final class FixP3L8AX3Shots: JIUITestCase {
    func testRG21_todayAtAX3HasNothingWiderThanTheScreen() {
        launch()
        let title = el("today.decide.title")
        reveal(title, "Today title", timeout: 40)
        _ = app.navigationBars["Health Access"].waitForExistence(timeout: 8); _ = declineHealthAccessSheet(); reveal(title, "Today title after the Health sheet", timeout: 15)
        let width = app.windows.firstMatch.frame.width
        var offenders: [String] = []
        for page in 0..<3 {
            shot("rg21-ax3-today-p\(page)")
            for e in app.descendants(matching: .any).allElementsBoundByIndex where e.exists {
                let f = e.frame
                // Decorative unlabeled images (the ambient backdrop glow) may bleed; content may not.
            guard f.width > 0, f.height > 0, f.width < width * 3,
                  !(e.elementType == .image && e.label.isEmpty && e.identifier.isEmpty) else { continue }
                if f.minX < -1 || f.maxX > width + 1 {
                    offenders.append("p\(page) \(e.elementType.rawValue) id=\(e.identifier) label=\(e.label.prefix(40)) x=\(Int(f.minX))..\(Int(f.maxX))")
                }
            }
            app.swipeUp()
        }
        tab("Training"); sleep(3)
        shot("rg21-ax3-training")
        for e in app.descendants(matching: .any).allElementsBoundByIndex where e.exists {
            let f = e.frame
            // Decorative unlabeled images (the ambient backdrop glow) may bleed; content may not.
            guard f.width > 0, f.height > 0, f.width < width * 3,
                  !(e.elementType == .image && e.label.isEmpty && e.identifier.isEmpty) else { continue }
            if f.minX < -1 || f.maxX > width + 1 {
                offenders.append("training \(e.elementType.rawValue) id=\(e.identifier) label=\(e.label.prefix(40)) x=\(Int(f.minX))..\(Int(f.maxX))")
            }
        }
        let report = Set(offenders).sorted().joined(separator: "\n")
        let a = XCTAttachment(string: report); a.name = "rg21-offenders"; a.lifetime = .keepAlways; add(a)
        if let shotsDir { try? report.write(toFile: shotsDir + "/rg21-offenders.txt", atomically: true, encoding: .utf8) }
        XCTAssertTrue(offenders.isEmpty, "wider than the screen:\n\(report)")
    }
}
