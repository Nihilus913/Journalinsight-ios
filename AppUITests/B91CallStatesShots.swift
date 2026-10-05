import XCTest

/// W-B91 S3 b91p4: the Strain card after the call, live. For each call (Full / Modified / Rest) the
/// test writes today's verdict-override on the throwaway hub (POST /planning/verdict-override, the
/// same write Adjust makes), relaunches with the gate forced open, and proves the card reads
/// "today · after your call" with Max today 60 / 40 / 20. Shots go to UITEST_SHOTS + the .xcresult.
/// Prod-clone hub only (UITEST_HUB_URL/TOKEN); never the prod hub.
final class B91CallStatesShots: JIUITestCase {
    func testB91p4_afterCallStatesFull60Modified40Rest20() throws {
        let morning = try hubGet("/api/v1/planning/morning") as? [String: Any]
        let date = try XCTUnwrap(morning?["verdict_date"] as? String, "hub has no verdict date")
        for (choice, max, name) in [("full", 60, "b91p4-1-full-60"), ("modified", 40, "b91p4-2-modified-40"),
                                    ("rest", 20, "b91p4-3-rest-20")] {
            try hubPostOverride(date: date, choice: choice)
            if app != nil { app.terminate() }
            launch()
            XCTAssertTrue(awaitDecide(), "Decide did not open (\(choice))")
            let card = el("today.decide.strain")
            // Decide can paint first from the SectionLoader's cached /morning (no override yet) and
            // only then re-seed from the fresh fetch — wait for the after-call state, never assert
            // on the first frame.
            let afterCall = expectation(for: NSPredicate(format: "label CONTAINS 'after your call'"),
                                        evaluatedWith: card)
            wait(for: [afterCall], timeout: 40)
            reveal(card, "Strain card (\(choice))")
            let range = el("today.decide.strain.range")
            let label = range.exists ? range.label : card.label
            XCTAssertTrue(label.contains("Max today \(max)"), "\(choice): expected Max today \(max), got \(label)")
            XCTAssertTrue(card.label.contains("after your call"), "\(choice): card not in the after-call state: \(card.label)")
            sleep(1)
            shot(name)
        }
    }

    /// The one write this proof makes — on the throwaway hub only (setUp refuses :8000).
    private func hubPostOverride(date: String, choice: String) throws {
        var req = URLRequest(url: URL(string: hubURL + "/api/v1/planning/verdict-override")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(hubToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date, "choice": choice,
                                                                    "reason": "b91p4 sim proof"])
        var status = 0
        let done = expectation(description: "POST override \(choice)")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        XCTAssertEqual(status, 200, "verdict-override \(choice) -> HTTP \(status)")
    }
}
