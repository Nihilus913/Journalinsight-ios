import Foundation
import SwiftUI
import Testing
import JICore
import JIPersistence
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

@MainActor
private func fix2Model(_ metric: KpiMetricId) throws -> KpiDetailViewModel {
    KpiDetailViewModel(
        metric: metric, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
}

// MARK: - BUG-22: the nutrition segment switches the whole screen (title, trend, alert)

@Test @MainActor func bug22SegmentSwitchesTheScreenMetricAndItsAlert() async throws {
    let vm = try fix2Model(.protein)
    await vm.load()
    #expect(vm.target?.metric == "avg_protein_7d")
    vm.selectMetric(.kcal)
    #expect(vm.metric == .kcal)
    #expect(vm.def.label == "Calories")                 // the navigation title
    #expect(vm.target?.metric == "avg_kcal_7d")          // the alert follows
    vm.selectMetric(.carbs)
    #expect(vm.def.label == "Carbs")
    #expect(vm.target == nil)                            // no carbs rule → no alert, never the old one
}

@Test @MainActor func bug22SegmentIgnoresANonNutritionMetric() async throws {
    let vm = try fix2Model(.protein)
    await vm.load()
    vm.selectMetric(.hrv)
    #expect(vm.metric == .protein)
    let steps = try fix2Model(.steps)
    steps.selectMetric(.kcal)
    #expect(steps.metric == .steps)
}

// MARK: - BUG-40: NormalBar replaces the line chart; the board's two links

@Test func bug40NutritionHasNoLineTrend() {
    for m in [KpiMetricId.kcal, .protein, .carbs, .fat] { #expect(kpiDetailShowsLineTrend(m) == false) }
    for m in [KpiMetricId.steps, .hrv, .rhr, .weight] { #expect(kpiDetailShowsLineTrend(m) == true) }
}

@Test func bug40BoardLinksInOrder() {
    #expect(KpiNutritionLink.allCases.map(\.title) == ["Put on a widget", "Edit macro goals"])
    let steps = kpiWidgetHowTo(metricLabel: "Protein")
    #expect(steps.contains { $0.contains("Protein") })
    #expect(steps.count >= 3)
}

// MARK: - BUG-09: a parent re-render hands the destination a fresh model; the screen keeps its own

#if canImport(UIKit)
@Test @MainActor func bug09ScreenKeepsTheModelItLoadedAcrossAParentRerender() async throws {
    let first = try fix2Model(.steps)
    let host = UIHostingController(rootView: KpiDetailView(model: first))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = host
    window.makeKeyAndVisible()
    for _ in 0..<100 where first.phase != .loaded {
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(first.phase == .loaded)
    // The navigation destination closure re-runs (tab focus, deep-link consumption) and builds a
    // brand-new, never-loaded model for the same screen.
    let second = try fix2Model(.steps)
    host.rootView = KpiDetailView(model: second)
    for _ in 0..<10 { host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
    // The screen must still be driven by the model it loaded — not a fresh idle one stuck on the
    // skeleton ("— No data") that nothing ever loads.
    #expect(KpiDetailView.debugLastRenderedModel.map(ObjectIdentifier.init) == ObjectIdentifier(first))
    window.isHidden = true
}
#endif
