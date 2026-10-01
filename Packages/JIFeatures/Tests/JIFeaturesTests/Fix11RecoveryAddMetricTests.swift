import Foundation
import Testing
@testable import JIFeatures

// W-FIX11 H2-11 (bug hunt 2026-10-01): Recovery's "Add a metric" opened Today's square picker
// ("Ticked ones sit on Today…"), and adding there never changed Recovery. It now adds back one of
// Recovery's own hidden squares (its Edit set), and is offered only when one is hidden.

@Test func addMetricAddsBackRecoverysOwnHiddenSquare() {
    let layout = recoveryTileLayout(orderRaw: "", hiddenRaw: "load")
    #expect(recoveryAddMetricHidden(after: layout) == "")
    #expect(recoveryTileLayout(orderRaw: "", hiddenRaw: recoveryAddMetricHidden(after: layout) ?? "load").visible.contains("load"))
}

@Test func nothingHiddenNoAddTile() {
    #expect(recoveryAddMetricHidden(after: recoveryTileLayout(orderRaw: "", hiddenRaw: "")) == nil)
}
