import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import JICore
import JIPersistence
import JIDesign
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

/// B-99 p5 — Nutrition › Diet quality card: hub first, Apple Health fallback, incomplete gate,
/// the always-on coverage caption, gallery entries, and (with `JI_PROOF_DIR`) sim proof PNGs.
@Suite struct DietQualityCardTests {
    @Test func completeHubDayShowsScoreBandAndCoverage() {
        let p = DietQualityFixtures.complete
        #expect(p.score == 73)   // HT diet_quality.py on the BP-20 day: fibre 61.3, sugar 61.3, sat fat 88.9, protein 81.9
        #expect(p.source == .hub)
        #expect(p.headline == "Mixed · fibre is the short one")
        #expect(p.caption == "Based on 73% of logged kcal · 3 meals logged")
        #expect(p.rows.map(\.key) == ["fibre", "sugar", "sat_fat", "protein"])
        #expect(p.rows.map(\.scoreText) == ["61", "61", "89", "82"])
        #expect(p.rows[0].detail == "13.9 g · aim 23 g (14 g per 1,000 kcal)")
        #expect(p.rows[1].detail == "64 g · 16% of kcal · aim ≤ 10%")
        #expect(p.rows[2].detail == "20 g · 11% of kcal · aim ≤ 10%")
        #expect(p.rows[3].detail == "127 g · goal 155 g")
    }

    @Test func incompleteDayHasNoScoreAndKeepsCaption() {
        let p = DietQualityFixtures.incomplete
        #expect(p.score == nil)
        #expect(p.state == .incomplete("Incomplete day · 2 of 3 meals"))
        #expect(p.headline == dietQualityGateCopy)
        #expect(p.caption == "Based on 23% of logged kcal · 2 meals logged")
        // Partial-day ratios are withheld ("—"), protein vs goal is shown.
        #expect(p.rows.map(\.scoreText) == ["—", "—", "—", "98"])
        #expect(p.rows[0].detail == "3.0 g so far")
    }

    @Test func noDataIsNeverAZero() {
        let p = dietQualityPresentation(date: "2026-10-04", hubRow: nil, health: nil, proteinGoal: 155, kcalGoal: 1617)
        #expect(p.state == .noData)
        #expect(p.rows.isEmpty)
        #expect(p.score == nil)
    }

    @Test func healthFallbackScoresFibreSugarProteinOnly() {
        let p = DietQualityFixtures.healthOnly
        #expect(p.source == .appleHealth)
        // (61.3 + 61.3 + 81.9) / 3 → n/a sat fat is left out of the weights, never 0.
        #expect(p.score == 68)
        #expect(p.rows.first { $0.key == "sat_fat" }?.scoreText == "n/a")
        #expect(p.rows.first { $0.key == "sat_fat" }?.detail == "Not in Apple Health")
        #expect(p.caption.hasPrefix("From Apple Health day totals"))
    }

    @Test func healthFallbackStillAppliesTheKcalGate() {
        let p = dietQualityPresentation(date: "2026-09-22", hubRow: nil,
                                        health: HealthDailyTotals(date: "2026-09-22", dietaryKcal: 700, proteinG: 60, fiberG: 9, sugarG: 20),
                                        proteinGoal: 155, kcalGoal: 1617)
        #expect(p.state == .incomplete("Incomplete day · under 60% of your kcal goal"))
    }

    @Test func hubDietQualityWinsOverHealthTotals() {
        let p = dietQualityPresentation(date: "2026-09-22", hubRow: DietQualityFixtures.completeRow,
                                        health: HealthDailyTotals(date: "2026-09-22", dietaryKcal: 1600, proteinG: 120, fiberG: 30, sugarG: 10),
                                        proteinGoal: 155, kcalGoal: 1617)
        #expect(p.source == .hub)
        #expect(p.score == 73)
    }

    @Test func oldHubWithoutDietQualityComputesOnDevice() {
        let row = NutritionDailyRow(date: "2026-09-22", kcalConsumed: 1620, kcalGoal: 1617, proteinG: 127, mealsLogged: 3,
                                    fiberG: 13.9, sugarG: 64)
        let p = dietQualityPresentation(date: "2026-09-22", hubRow: row, health: nil, proteinGoal: 155, kcalGoal: 1617)
        #expect(p.source == .onDevice)
        #expect(p.score == 68)
        #expect(p.caption == "Coverage of logged kcal unknown · 3 meals logged")
    }

    @Test func bandWordsHaveNoPenaltyFraming() {
        #expect(dietQualityBand(85) == "Strong")
        #expect(dietQualityBand(72) == "Mixed")
        #expect(dietQualityBand(40) == "Room to grow")
    }

    @Test func galleryHasTheDietQualityRoutes() {
        let names = ScreenRegistry.entries.map(\.name)
        #expect(names.contains("Diet quality"))
        #expect(names.contains("Diet quality method"))
    }

    @Test @MainActor func viewModelReadsTheHubRowForTheSelectedDay() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let vm = NutritionViewModel(provider: DQFixtureProvider(), cache: cache, initialDate: "2026-09-22",
                                    healthFeed: HealthDailyTotalsFeed())
        await vm.load()
        #expect(vm.hubDayRow?.dietQuality?.score == 73)
        #expect(vm.dietQuality(proteinGoal: 155, kcalGoal: 1617).score == 73)
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Sim proof: the gallery routes rendered through a real UIWindow at iPhone 18 Pro size, light
    /// and dark. Writes PNGs only when `JI_PROOF_DIR` is set (`TEST_RUNNER_JI_PROOF_DIR=…`).
    @Test @MainActor func proofRender() throws {
        let outDir = ProcessInfo.processInfo.environment["JI_PROOF_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        let entries = ScreenRegistry.entries.filter { $0.slug.hasPrefix("diet-quality") }
        #expect(entries.count == 2)
        for entry in entries {
            for dark in [false, true] {
                let image = try #require(render(entry, width: 402, height: 1500, dark: dark))
                #expect(image.width == 804)
                if let outDir {
                    let url = outDir.appendingPathComponent("\(entry.slug)-\(dark ? "dark" : "light").png")
                    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(dest, image, nil)
                    #expect(CGImageDestinationFinalize(dest))
                }
            }
        }
    }

    @MainActor private func render(_ entry: ScreenEntry, width: CGFloat, height: CGFloat, dark: Bool) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let host = UIHostingController(rootView: entry.make().jiTheme(entry.theme).jiRevealAnimations(false))
        host.view.frame = bounds
        host.traitOverrides.userInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(frame: bounds)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
        }
        window.isHidden = true; window.rootViewController = nil
        return image.cgImage
    }
    #endif
}

private struct DQFixtureProvider: NutritionProviding {
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] {
        [DietQualityFixtures.completeRow, DietQualityFixtures.incompleteRow]
    }
}
