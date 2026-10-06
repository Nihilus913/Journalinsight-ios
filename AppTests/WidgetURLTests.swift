import Foundation
import Testing
import JICore
@testable import JournalInsight

// RG-80: gate widget, KPI widget and verdict Live Activity carry a widgetURL the app parses.
@Suite struct WidgetURLTests {
    @Test func gateURLOpensDecide() {
        #expect(WidgetDeepLinks.gate.absoluteString == "ji://gate")
        #expect(DeepLink.parse(WidgetDeepLinks.gate) == .gate)
    }

    @Test func kpiURLOpensThatMetricsDetail() {
        for metric in [KpiMetricId.hrv, .bodyBattery, .readiness] {
            let url = WidgetDeepLinks.kpiDetail(metric)
            #expect(url.absoluteString == "ji://kpi-detail?metric=\(metric.rawValue)")
            #expect(DeepLink.parse(url) == .kpiDetail(metric: metric.rawValue))
            #expect(RootRoute.destination(for: DeepLink.parse(url)!) == .kpiDetail(metric: metric.rawValue))
        }
    }
}
