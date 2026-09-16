import Testing
import Foundation
@testable import JournalInsight

@Test func jiSchemeGateParses() {
    #expect(DeepLink.parse(URL(string: "ji://gate")!) == .gate)
}

@Test func journalinsightSchemeGateParses() {
    #expect(DeepLink.parse(URL(string: "journalinsight://gate")!) == .gate)
}

@Test func kpiDetailWithMetricParses() {
    #expect(DeepLink.parse(URL(string: "ji://kpi-detail?metric=hrv")!) == .kpiDetail(metric: "hrv"))
}

@Test func unknownHostReturnsNil() {
    #expect(DeepLink.parse(URL(string: "ji://unknown")!) == nil)
}

@Test func nonJiSchemeReturnsNil() {
    #expect(DeepLink.parse(URL(string: "https://example.com/gate")!) == nil)
}

@Test func kpiDetailMissingMetricReturnsNil() {
    #expect(DeepLink.parse(URL(string: "ji://kpi-detail")!) == nil)
}

@Test func kpiDetailMissingMetricEmptyValueReturnsNil() {
    #expect(DeepLink.parse(URL(string: "ji://kpi-detail?metric=")!) == nil)
}

// Path-shaped variant (no host) — some hand-typed/share-sheet URLs collapse this way.
@Test func pathShapedGateParses() {
    #expect(DeepLink.parse(URL(string: "ji:///gate")!) == .gate)
}
