import Foundation
import Testing
import JICore
import JIHub
import JIPersistence
import SwiftUI
import JIDesign
@testable import JIFeatures
#if canImport(UIKit) && !os(watchOS)
import UIKit
import ImageIO
import UniformTypeIdentifiers
#endif

// B-57 W1 r5 fixer h3 — More tab trailing values, the Data quality footer copy, and the Settings
// entry to the Weekly plan seeding from the real goals document.

// MARK: - More rows

@Test func moreNutritionShowsTodaysKcalOverTheGoal() {
    #expect(moreNutritionValue(consumedKcal: 467.4, goalKcal: 1617).text == "467 / 1617 kcal")
    #expect(moreNutritionValue(consumedKcal: 467, goalKcal: 1617).style == .kcal)
    #expect(moreNutritionValue(consumedKcal: 467, goalKcal: nil).text == "467 kcal")
    #expect(moreNutritionValue(consumedKcal: nil, goalKcal: 1617).text == "— No data")
}

@Test func moreEnergyUsesTheHeroNumeralAndItsTrackingGate() {
    // deficit 598 (eating less than burnt) reads as a −598 balance, like the Energy hero.
    #expect(moreEnergyValue(avgDeficit7d: 598, trackingDays: 7).text == "\u{2212}598 7-day avg vs TDEE")
    #expect(moreEnergyValue(avgDeficit7d: 598, trackingDays: 3).text == "— No data")
    #expect(moreEnergyValue(avgDeficit7d: nil, trackingDays: 7).text == "— No data")
}

@Test func moreGoalsShowsLatestWeightToTarget() {
    #expect(moreGoalsValue(currentKg: 80.24, targetKg: 75).text == "80.2 → 75.0 kg")
    #expect(moreGoalsValue(currentKg: nil, targetKg: 75).text == "— → 75.0 kg")
    #expect(moreGoalsValue(currentKg: 80.2, targetKg: nil).text == "— No goal set")
}

@Test func moreMindShowsLatestWho5Percent() {
    #expect(moreMindValue(who5Pct: 64).text == "WHO-5 64%")
    #expect(moreMindValue(who5Pct: nil).text == "WHO-5 — No data")
}

// MARK: - Data quality footer

@MainActor @Test func dataQualityFooterIsTheBoardCopyNeverTheHubDiagnostic() async {
    let model = DataQualityViewModel(provider: MockDataProvider())
    await model.load()
    #expect(model.provenanceGap == "Provenance is not scored yet.")
    #expect(model.provenanceGap?.contains("E14") == false)
}

// MARK: - Settings → Weekly plan

@MainActor @Test func settingsWeeklyPlanSeedsFromTheGoalsProvider() async throws {
    let settings = SettingsViewModel(store: ConnectionConfigStore(secrets: InMemorySecretStore()),
                                     prefs: PrefStore(db: try AppDatabase.inMemory()),
                                     goalsProvider: MockDataProvider(), onSaved: { _ in })
    let plan = settings.makeWeeklyPlanModel()
    await plan.load()
    // B-57 W2 (B-73): the hub document still seeds the plan's numbers, but its seeded kcal is not
    // the user's goal — with no JI goal saved, "Matches your goal" has nothing to match.
    #expect(plan.weeklyAvgKcal == 1935)
    #expect(plan.goalKcal == nil)

    let bare = SettingsViewModel(store: ConnectionConfigStore(secrets: InMemorySecretStore()),
                                 prefs: PrefStore(db: try AppDatabase.inMemory()), onSaved: { _ in })
    let noGoal = bare.makeWeeklyPlanModel()
    await noGoal.load()
    #expect(noGoal.goalKcal == nil)
}

// MARK: - Opt-in proof render of the More rows (TEST_RUNNER_JI_H3_PROOF_DIR)

#if canImport(UIKit) && !os(watchOS)
@MainActor
private struct MoreProofList: View {
    let nutrition, energy, goals, mind: MoreRowValue
    var body: some View {
        NavigationStack {
            List {
                Section("Track") {
                    NavigationLink { EmptyView() } label: { MoreRowLabel("Nutrition", systemImage: "fork.knife", value: nutrition) }
                    NavigationLink { EmptyView() } label: { MoreRowLabel("Energy", systemImage: "flame", value: energy) }
                    NavigationLink { EmptyView() } label: { LabeledContent { Text("6 chosen") } label: { Label("My KPIs", systemImage: "chart.bar") } }
                    NavigationLink { EmptyView() } label: { MoreRowLabel("Goals", systemImage: "target", value: goals) }
                }
                Section("Practice") {
                    NavigationLink { EmptyView() } label: { MoreRowLabel("Mind", systemImage: "water.waves", value: mind) }
                }
            }
            .navigationTitle("More")
            .navigationSubtitle("Everything that is not a daily decision")
        }
    }
}

@MainActor
private func h3Render(_ view: some View, ax3: Bool, to url: URL) {
    let bounds = CGRect(x: 0, y: 0, width: 393, height: ax3 ? 1400 : 852)
    let root = view.jiTheme(.native).jiRevealAnimations(false).dynamicTypeSize(ax3 ? .accessibility3 : .large)
    let host = UIHostingController(rootView: root)
    host.view.frame = bounds
    host.view.backgroundColor = .systemBackground
    host.traitOverrides.userInterfaceStyle = .dark
    let window = UIWindow(frame: bounds)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.isHidden = false
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    CATransaction.flush()
    let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
    let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
        if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
    }
    window.isHidden = true; window.rootViewController = nil
    guard let cg = image.cgImage,
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { Issue.record("could not render \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}

@MainActor @Test func moreRowsProofRender() throws {
    guard let dir = ProcessInfo.processInfo.environment["JI_H3_PROOF_DIR"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // Board-shaped figures run through the real formatters; then the all-missing state.
    let filled = MoreProofList(nutrition: moreNutritionValue(consumedKcal: 467, goalKcal: 1617),
                               energy: moreEnergyValue(avgDeficit7d: 598, trackingDays: 7),
                               goals: moreGoalsValue(currentKg: 80.2, targetKg: 75),
                               mind: moreMindValue(who5Pct: 64))
    let missing = MoreProofList(nutrition: moreNutritionValue(consumedKcal: nil, goalKcal: nil),
                                energy: moreEnergyValue(avgDeficit7d: nil, trackingDays: 0),
                                goals: moreGoalsValue(currentKg: nil, targetKg: nil),
                                mind: moreMindValue(who5Pct: nil))
    for (name, view) in [("more-filled", filled), ("more-missing", missing)] {
        h3Render(view, ax3: false, to: out.appendingPathComponent("\(name)-default.png"))
        h3Render(view, ax3: true, to: out.appendingPathComponent("\(name)-ax3.png"))
    }
}
#endif
