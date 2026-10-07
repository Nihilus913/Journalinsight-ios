import Foundation
import JICore
import JIDesign
import Testing
@testable import JIFeatures

/// W-OFFLINE2 OFF2-3: a needs-hub card (Energy, Nutrition, Training with no hub) shows the honest
/// line and NO Retry action — Retry only re-settled the same line. A live (hub) card keeps Retry.
@Suite struct NeedsHubTests {
    @Test func needsHubOffersNoRetry() {
        #expect(HubAvailability.needsHub.offersRetry == false)
        #expect(HubAvailability.live.offersRetry == true)
    }

    /// Every hub-only screen's error card gates its Retry button on `offersRetry`.
    @Test func errorCardsGateRetryOnAvailability() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JIFeatures")
        for file in ["Energy/EnergyView.swift", "Nutrition/NutritionView.swift", "Training/TrainingView.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let card = try #require(text.range(of: "private func errorCard("), "\(file)")
            let body = text[card.lowerBound...].prefix(900)
            let gate = try #require(body.range(of: "if model.availability.offersRetry {"), "\(file) has no gate")
            let retry = try #require(body.range(of: "Button(\"Retry\")"), "\(file)")
            #expect(gate.upperBound <= retry.lowerBound, "\(file): Retry outside the gate")
        }
    }

    /// The Recovery Body Battery tile off the hub uses the short word, so its one-line caption fits.
    @Test func recoveryBatteryCaptionIsTheShortWord() {
        let readings = recoveryWatchReadings(days: [], today: "2026-10-07", capabilities: .appleWatchCapabilities)
        let battery = readings.first { $0.id == "bodyBattery" }
        #expect(battery?.caption == "Needs the hub")
        #expect((battery?.caption.count ?? 99) <= JISignalStatus.squareWordMaxLength)
    }
}
