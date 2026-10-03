import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// W-KEYS D2r (audit P8, Toby D2 2026-10-03): one icon per metric, aligned on every screen. The
/// Today grid used to draw `bed.double.fill` / `dumbbell.fill` / `bolt.heart.fill` for the same
/// metrics EditToday and My KPIs drew as `moon` / `bolt` / `gauge.medium`. Every surface now reads
/// `KpiMetrics.def(id).symbol`.
struct KpiDescriptorTests {
    @Test func oneIconPerMetric() {
        let catalogue = kpiCatalogueItems(group: .onToday, visible: KpiMetricId.allCases, value: { _ in nil },
                                          today: "2026-10-03", goalCaption: { _, _ in nil }, load: nil, health: [])
        for id in KpiMetricId.allCases {
            let symbol = KpiMetrics.def(id).symbol
            let note = Comment(rawValue: id.rawValue)
            // EditToday / My KPIs "On Today" registry
            #expect(TodayTileRegistry.systemImage(for: id.rawValue) == symbol, note)
            // Today grid card
            let chip = TodayChip(id: id.rawValue, label: "x", value: nil, unit: nil, points: [], sourceMissing: false)
            #expect(todaySummaryCardSpec(for: chip).icon == symbol, note)
            // My KPIs catalogue square
            #expect(catalogue.first { $0.id == id.rawValue }?.systemImage == symbol, note)
        }
    }

    /// Trends and Recovery key their cards by display ids ("load"); those resolve through the
    /// same alias map, so their icons are the descriptor's too.
    @Test func trendsAndRecoveryUseTheDescriptorIcon() throws {
        for card in trendsCards(recovery: [], daily: [], averages: nil) {
            let id = try #require(KpiMetricId(normalizing: card.id))
            #expect(card.systemImage == KpiMetrics.def(id).symbol, Comment(rawValue: card.id))
        }
        let layout = recoveryTileLayout(orderRaw: "", hiddenRaw: "")
        for item in recoveryTileItems(days: [], layout: layout, editing: false) {
            let id = try #require(KpiMetricId(normalizing: item.id))
            #expect(item.systemImage == KpiMetrics.def(id).symbol, Comment(rawValue: item.id))
        }
        for metric in RecoveryCardMetric.allCases {
            #expect(metric.symbol == KpiMetrics.def(try #require(KpiMetricId(normalizing: metric.kpiId))).symbol)
        }
    }

    /// The registry's labels and decimals come off the same table (D2r).
    @Test func registryReadsTheDescriptor() {
        #expect(TodayTileRegistry.ids == TodayTileRegistry.metrics.map(\.rawValue))
        for id in KpiMetricId.allCases {
            #expect(TodayTileRegistry.label(for: id.rawValue) == KpiMetrics.def(id).shortLabel)
            #expect(TodayTileRegistry.decimals(for: id.rawValue) == KpiMetrics.def(id).decimals)
        }
    }
}
