import Foundation
import Testing
import JICore
import JIHub
import JIPersistence
@testable import JIFeatures

// W-FIX3 fixer C-e: Settings → My KPIs squares open their KPI detail (as the shell's My KPIs
// sheet does since W-FIX2 BUG-21). Before: `KpiListView` was built without `onSelectKpi`.

@MainActor
private func makeModel(detail: (@MainActor (KpiMetricId) -> KpiDetailViewModel?)?) throws -> SettingsViewModel {
    SettingsViewModel(
        store: ConnectionConfigStore(secrets: InMemorySecretStore()),
        prefs: PrefStore(db: try AppDatabase.inMemory()),
        makeKpiDetailModel: detail,
        onSaved: { _ in }
    )
}

@Test @MainActor func settingsKpiSquareTapRoutesToItsDetail() throws {
    let model = try makeModel(detail: { _ in nil })
    let select = try #require(model.kpiSelectAction, "a detail factory must make the squares tappable")
    select("hrv")
    #expect(model.kpiDetailMetric == .hrv)
    select("protein")
    #expect(model.kpiDetailMetric == .protein)
}

@Test @MainActor func settingsKpiSquareIgnoresUnknownIds() throws {
    let model = try makeModel(detail: { _ in nil })
    model.kpiSelectAction?("not-a-kpi")
    #expect(model.kpiDetailMetric == nil)
}

@Test @MainActor func settingsKpiSquaresAreDisplayOnlyWithoutADetailFactory() throws {
    let model = try makeModel(detail: nil)
    #expect(model.kpiSelectAction == nil)
}

@Test @MainActor func settingsKpiDetailModelIsBuiltOncePerTap() throws {
    var built: [KpiMetricId] = []
    let model = try makeModel(detail: { built.append($0); return nil })
    model.kpiSelectAction?("hrv")
    _ = model.kpiDetailModel; _ = model.kpiDetailModel
    #expect(built == [.hrv])
}
