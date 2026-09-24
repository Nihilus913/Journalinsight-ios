import Testing
import JICore
import JIDesign
@testable import JIFeatures

struct KpiCatalogueTests {
    @Test func everyKpiHasOneGroup() {
        #expect(kpiCatalogueGroup(.hrv) == .recovery)
        #expect(kpiCatalogueGroup(.protein) == .nutrition)
        #expect(kpiCatalogueGroup(.weight) == .body)
        #expect(kpiCatalogueGroup(.steps) == .body)
    }

    @Test func onTodayIsTickedAndTheRestOfferAdd() {
        let visible: [KpiMetricId] = [.hrv, .sleep]
        let onToday = kpiCatalogueItems(group: .onToday, visible: visible, value: { _ in nil })
        #expect(onToday.map(\.id) == ["hrv", "sleep"])
        #expect(onToday.allSatisfy { $0.badge == .selected })
        let recovery = kpiCatalogueItems(group: .recovery, visible: visible, value: { _ in nil })
        #expect(!recovery.map(\.id).contains("hrv"))
        #expect(recovery.allSatisfy { $0.badge == .add })
    }

    @Test func fibreAndSugarAreDisplayOnlyNoData() {
        let n = kpiCatalogueItems(group: .nutrition, visible: [], value: { _ in 100 })
        let fibre = n.first { $0.id == "fibre" }
        #expect(fibre?.value == nil)
        #expect(fibre?.status == .missing(.noData))
        #expect(fibre?.badge == JISquareBadge.none)
    }

    @Test func missingValuesAreNoDataNeverZero() {
        let r = kpiCatalogueItems(group: .recovery, visible: [], value: { _ in nil })
        #expect(r.allSatisfy { $0.value == nil && $0.status == .missing(.noData) })
    }
}
