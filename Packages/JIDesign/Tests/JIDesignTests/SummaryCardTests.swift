import SwiftUI
import Testing
@testable import JIDesign

@Test func summaryCardLabelReadsTitleValueUnitTimestamp() {
    #expect(summaryCardAccessibilityLabel(title: "HRV", value: "52", unit: "ms", timestamp: "Today, 07:12", sourceMissing: false) == "HRV 52 ms, Today, 07:12")
}

@Test func summaryCardLabelWithoutValueSaysNoData() {
    #expect(summaryCardAccessibilityLabel(title: "HRV", value: nil, unit: "ms", timestamp: nil, sourceMissing: false) == "HRV, no data yet")
}

@Test func summaryCardLabelSourceMissingUsesSharedCopy() {
    #expect(summaryCardAccessibilityLabel(title: "Body Battery", value: nil, unit: nil, timestamp: nil, sourceMissing: true) == "Body Battery \(sourceMissingCopy)")
}

@Test @MainActor func summaryCardRenders() {
    expectRenders("SummaryCard") {
        SummaryCard(icon: "waveform.path.ecg", tint: .red, title: "HRV", value: "52", unit: "ms", timestamp: "Today, 07:12", sparkline: [48, 50, 47, 53, 51, 49, 52], action: {})
    }
    expectRenders("SummaryCard gated") {
        SummaryCard(icon: "battery.75percent", tint: .teal, title: "Body Battery", value: nil, sourceMissing: true)
    }
}

// MARK: - B-47 regression: the numeral must never wrap in the two-up Today grid.

@MainActor private func renderedHeight<V: View>(_ width: CGFloat, @ViewBuilder _ view: () -> V) -> CGFloat {
    let renderer = ImageRenderer(content: view().frame(width: width).jiTheme(.native))
    guard let image = renderer.cgImage else { return 0 }
    return CGFloat(image.height) / renderer.scale
}

/// `family: nil` hugs content so the composition can be measured; the app's cards are `.square`.
@MainActor private func stepsCard(_ value: String, sparkline: [Double?] = [], family: JITileHeight? = nil) -> SummaryCard {
    SummaryCard(icon: "figure.walk", tint: .green, title: "Steps", value: value, unit: "steps",
                timestamp: "Today, 07:12", sparkline: sparkline, family: family, action: {})
}

/// W-GUI F7 (DEV-06): in the `.square` family the card is 172 pt at the default size whatever
/// its content — a sparkline, a long value, a missing timestamp never change the height.
@Test @MainActor func squareFamilyCardIsAlwaysTheFamilyHeight() {
    let spark: [Double?] = [4100, 5200, 3900, 6800, 5100, 4700, 6420]
    let plain = renderedHeight(190) { stepsCard("64", family: .square) }
    #expect(plain == JITileHeight.square.base)
    #expect(renderedHeight(190) { stepsCard("6'420", sparkline: spark, family: .square) } == plain)
    #expect(renderedHeight(361) { stepsCard("6'420", sparkline: spark, family: .square) } == plain)
}

/// THE B-47 REGRESSION. In the two-up grid the value sits beside a 64 pt sparkline, so the
/// numeral is offered ≈80 pt. Toby's step counts are 4–5 digits every day, and before the fix
/// "6'420" broke into "6'4" / "20". The numeral must stay on ONE line at every squeeze width —
/// it shrinks (`minimumScaleFactor`) rather than wrapping.
@Test @MainActor func summaryCardNumeralNeverWrapsWhenSqueezed() {
    let oneLine = renderedHeight(200) { stepsCard("64").numeral }
    for width in [60.0, 70.0, 82.0, 100.0, 158.0] as [CGFloat] {
        let wide = renderedHeight(width) { stepsCard("6'420").numeral }
        #expect(wide > 0, "numeral rendered at \(width) pt")
        // One line, never two. A squeezed numeral may be SHORTER (minimumScaleFactor), never taller.
        #expect(wide <= oneLine, "\"6'420\" wrapped at \(width) pt: \(wide) pt vs one line \(oneLine) pt")
    }
}

/// Whole card without a sparkline: any height change with the value's width is a wrapped number.
@Test @MainActor func summaryCardWithoutSparklineIsValueWidthIndependent() {
    for width in [180.0, 190.0, 200.0] as [CGFloat] {
        #expect(renderedHeight(width) { stepsCard("6'420") } == renderedHeight(width) { stepsCard("64") },
                "card height changed with the value width at \(width) pt")
    }
}

/// At half width the sparkline moves to its own row (Apple Fitness idiom) instead of squeezing
/// the value; at full width the old one-row composition is kept.
@Test @MainActor func sparklineMovesBelowTheValueOnlyAtHalfWidth() {
    let spark: [Double?] = [4100, 5200, 3900, 6800, 5100, 4700, 6420]
    #expect(renderedHeight(190) { stepsCard("6'420", sparkline: spark) }
            > renderedHeight(190) { stepsCard("6'420") })
    // W-GUI S1/T3: the sparkline now carries its axis words (taller than the value row), so at
    // full width the card grows by the sparkline's own height — but it stays BESIDE the value:
    // the full-width card is never as tall as the half-width (stacked) one.
    #expect(renderedHeight(361) { stepsCard("6'420", sparkline: spark) }
            < renderedHeight(190) { stepsCard("6'420", sparkline: spark) })
}

@Test @MainActor func summaryCardRendersAtHalfWidth() {
    expectRenders("SummaryCard two-up", width: 190) {
        stepsCard("6'420", sparkline: [4100, 5200, 3900, 6800, 5100, 4700, 6420])
    }
}
