import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import JICore
import JIDesign
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

/// RG-44 / RG-45 (W-FIX-P2, B-99): a 0-meal day is the no-data state (not "Incomplete · 0 of 3
/// meals", no "Not in the logged food" ×4); protein alone is not scored; the method sheet says
/// "three contributors" while saturated fat is not in the food log.
@Suite struct DietQualityNoDataTests {
    private func contributors(_ sat: Double?) -> [DietQualityDTO.Contributor] {
        [.init(key: "fibre"), .init(key: "sugar"), .init(key: "sat_fat", score: sat), .init(key: "protein", score: 0)]
    }

    @Test func hubNoDataReasonIsTheNoDataState() {
        let row = NutritionDailyRow(date: "2026-10-05", kcalConsumed: 0, proteinG: 0, mealsLogged: 0,
                                    dietQuality: DietQualityDTO(incomplete: true, reason: "no_data", contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-10-05", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.state == .noData)
        #expect(p.rows.isEmpty)
        #expect(p.caption == "No food logged for this day.")
        #expect(!p.headline.contains("0 of 3"))
    }

    @Test func zeroMealRowWithoutHubScoreIsNoData() {
        let row = NutritionDailyRow(date: "2026-10-05", kcalConsumed: 0, proteinG: 0, mealsLogged: 0)
        let p = dietQualityPresentation(date: "2026-10-05", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.state == .noData)
    }

    @Test func proteinOnlyLineNamesTheMissingFoodDetail() {
        let row = NutritionDailyRow(date: "2026-09-21", kcalConsumed: 1800, proteinG: 140, mealsLogged: 3,
                                    dietQuality: DietQualityDTO(incomplete: true, reason: "no_contributors",
                                                                contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-09-21", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.score == nil)
        #expect(p.state == .incomplete("Incomplete day · no fibre, sugar or saturated-fat detail"))
    }

    @Test func methodSheetSaysThreeContributorsWithoutSatFat() {
        let row = NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1800, proteinG: 150, mealsLogged: 3,
                                    fiberG: 18, sugarG: 40, satFatG: nil,
                                    dietQuality: DietQualityDTO(score: 70, incomplete: false, contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-09-28", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.satFatInData == false)
        let steps = dietQualityMethodSteps(satFatInData: p.satFatInData)
        #expect(steps[0].title == "Three contributors, 0–100 each")
        #expect(!steps.map(\.body).joined().contains("fibre, sugar and saturated-fat detail"))
    }

    @Test func methodSheetSaysFourContributorsWithSatFat() {
        let row = NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1800, proteinG: 150, mealsLogged: 3,
                                    fiberG: 18, sugarG: 40, satFatG: 20,
                                    dietQuality: DietQualityDTO(score: 70, incomplete: false, contributors: contributors(90)))
        let p = dietQualityPresentation(date: "2026-09-28", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.satFatInData)
        #expect(dietQualityMethodSteps(satFatInData: true)[0].title == "Four contributors, 0–100 each")
    }

    #if canImport(UIKit)
    /// Sim proof (RG-44 / RG-45): the 0-meal day card and the three-contributor sheet, written as
    /// PNGs when `JI_PROOF_DIR` is set (`TEST_RUNNER_JI_PROOF_DIR=…`).
    @Test @MainActor func proofRenderZeroMealDayAndSheet() throws {
        let row = NutritionDailyRow(date: "2026-10-05", kcalConsumed: 0, proteinG: 0, mealsLogged: 0,
                                    dietQuality: DietQualityDTO(incomplete: true, reason: "no_data", contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-10-05", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        let scored = NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1800, proteinG: 150, mealsLogged: 3,
                                       fiberG: 18, sugarG: 40, satFatG: nil,
                                       dietQuality: DietQualityDTO(score: 84, incomplete: false, contributors: [
                                           .init(key: "fibre", score: 51.0, weight: 1.0 / 3), .init(key: "sugar", score: 100, weight: 1.0 / 3),
                                           .init(key: "sat_fat"), .init(key: "protein", score: 100, weight: 1.0 / 3)], coveragePct: 67))
        let p28 = dietQualityPresentation(date: "2026-09-28", hubRow: scored, health: nil, proteinGoal: 150, kcalGoal: 1935)
        let outDir = ProcessInfo.processInfo.environment["JI_PROOF_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        let shots: [(String, AnyView)] = [
            ("rg44-diet-quality-0-meal-day", AnyView(ScrollView { DietQualityCard(model: p, onShowMethod: {}).padding() })),
            ("rg45-diet-quality-sheet-three", AnyView(DietQualitySheet(model: p28))),
        ]
        for (name, view) in shots {
            let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
            let host = UIHostingController(rootView: view.jiTheme(.native))
            host.view.frame = bounds
            let window = UIWindow(frame: bounds)
            window.rootViewController = host
            window.isHidden = false
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            CATransaction.flush()
            let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
            let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
                if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
            }
            window.isHidden = true; window.rootViewController = nil
            let cg = try #require(image.cgImage)
            if let outDir {
                let url = outDir.appendingPathComponent("\(name).png")
                let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(dest, cg, nil)
                #expect(CGImageDestinationFinalize(dest))
            }
        }
    }
    #endif
}
