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

// W-B102 C-5: the data-triggered check-in's notification URL.
@Test func checkInParsesWithAndWithoutTrigger() {
    #expect(DeepLink.parse(URL(string: "ji://checkin?trigger=amber2")!) == .checkIn(trigger: "amber2"))
    #expect(DeepLink.parse(URL(string: "journalinsight://checkin")!) == .checkIn(trigger: nil))
    #expect(DeepLink.parse(URL(string: "ji://checkin?trigger=")!) == .checkIn(trigger: nil))
    #expect(RootRoute.destination(for: .checkIn(trigger: "amber2")) == nil)
}

// B-43 P1: the rest-end alert / strength Live Activity open the set logger.
@Test func strengthLogParses() {
    #expect(DeepLink.parse(URL(string: "ji://strength-log")!) == .strengthLog)
    #expect(DeepLink.parse(URL(string: "ji:///strength-log")!) == .strengthLog)
    #expect(RootRoute.destination(for: .strengthLog) == nil)
}

// RG-65: a cardio day's workout-day nudge opens Training (never the strength logger).
@Test func trainingLinkParses() {
    #expect(DeepLink.parse(URL(string: "ji://training")!) == .training)
    #expect(DeepLink.parse(URL(string: "ji:///training")!) == .training)
    #expect(RootRoute.destination(for: .training) == nil)
}
