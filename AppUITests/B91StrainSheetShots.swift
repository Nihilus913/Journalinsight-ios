import XCTest

/// W-B91 S3 b91p2: tap the Strain card on Decide → the Strain detail sheet (strain + usual range,
/// the Exercise-minutes Load figure, acute / chronic / ratio tiles and the named status word).
/// Run against a prod-clone hub (UITEST_HUB_URL/TOKEN); shots go to UITEST_SHOTS and the .xcresult.
final class B91StrainSheetShots: JIUITestCase {
    func testB91p2_strainCardOpensDetailSheet() {
        launch()
        XCTAssertTrue(awaitDecide(), "Decide did not open")
        let card = el("today.decide.strain")
        reveal(card, "Strain card")
        shot("b91p2-1-decide-strain-card")
        card.tap()
        let status = el("today.decide.strainDetail.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Strain sheet did not open")
        XCTAssertTrue(el("today.decide.strainDetail.tile.acute").exists, "no acute tile")
        XCTAssertTrue(el("today.decide.strainDetail.tile.chronic").exists, "no chronic tile")
        XCTAssertTrue(el("today.decide.strainDetail.tile.ratio").exists, "no ratio tile")
        XCTAssertTrue(el("today.decide.strainDetail.minutes").exists, "no minutes Load figure")
        XCTAssertFalse(status.label.isEmpty, "status word empty")
        sleep(1)
        XCTAssertTrue(el("today.decide.strainDetail.tile.ratio").isHittable, "ratio tile not on screen")
        shot("b91p2-2-strain-detail-sheet")
    }
}
