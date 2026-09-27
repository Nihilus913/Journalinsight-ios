import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI T7 — Edit Today (15) + Add a square (16): catalogue rows, tick state, captions.
@Test func catalogueRowTextCarriesTheValueOrTheReason() {
    #expect(editTodayCatalogueRowText(JISquareItem(id: "kcal", label: "Calories", value: 1183, unit: "kcal", badge: .add)) == "Calories · 1183 kcal")
    #expect(editTodayCatalogueRowText(JISquareItem(id: "protein", label: "Protein", value: 98, unit: "g", badge: .selected)) == "Protein · 98 g")
    #expect(editTodayCatalogueRowText(JISquareItem(id: "acwr", label: "Load", value: nil, status: .missing(.calibrating), badge: .add)) == "Load · Calibrating")
    #expect(editTodayCatalogueRowText(JISquareItem(id: "w", label: "Weight", value: nil, badge: .add)) == "Weight · No data")
}

@Test func tickStateFollowsTheBadge() {
    #expect(editTodayCatalogueRowIsOn(JISquareItem(id: "a", label: "A", value: nil, badge: .selected)))
    #expect(!editTodayCatalogueRowIsOn(JISquareItem(id: "a", label: "A", value: nil, badge: .add)))
}

@Test func captionsAndTheAddSquareLabel() {
    #expect(addSquareLabel == "Add a square")
    #expect(editTodayCatalogueCaption == "Tick to add. Squares keep their size; the grid stays three wide.")
    #expect(editTodayCaption.contains("Today holds \(KpiSelection.minSelected) to \(KpiSelection.maxSelected) squares"))
    #expect(squareTileFamily(catalog: true).base == 104)
}
