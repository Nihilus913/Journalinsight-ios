import Foundation
import Testing
import JICore
@testable import JISnapshot

/// W-B78 B78-1: the phone → watch WatchConnectivity wire for the `HubSnapshot`.
@Suite
struct SnapshotWireTests {
    static func full(allKpis: [SnapshotKPI]? = nil) -> HubSnapshot {
        HubSnapshot(
            verdictWord: "REDUCED (session)", verdictSession: "Upper A, -1 set", verdictTone: "amber",
            verdictDate: "2026-10-06", readiness: 71.5,
            kpis: [SnapshotKPI(id: .hrv, label: "HRV", value: 58, unit: "ms", normalLow: 52, normalHigh: 66),
                   SnapshotKPI(label: "Sleep", value: nil, unit: nil)],
            allKpis: allKpis ?? [SnapshotKPI(id: .rhr, label: "RHR", value: 49, unit: "bpm")],
            fetchedAt: Date(timeIntervalSince1970: 1_791_300_000.25), lastSync: Date(timeIntervalSince1970: 1_791_299_000),
            macros: SnapshotMacros(kcal: SnapshotMacro(goal: 2400, left: 900), protein: nil, carbs: nil, fat: nil,
                                   asOf: Date(timeIntervalSince1970: 1_791_290_000)),
            reason: "HRV below normal", planDone: 2, planTotal: 4, hrCap: 175, nextSession: "Fri · Day 3 Full Upper",
            signals: [SnapshotSignal(key: "hrv", label: "HRV", value: 58, unit: "ms", normalLow: 52, normalHigh: 66, goal: nil, status: "amber")]
        )
    }

    @Test func keyIsStable() { #expect(SnapshotWire.key == "ji.snapshot") }

    @Test func roundTripsEveryField() throws {
        let s = Self.full()
        #expect(SnapshotWire.decode(try SnapshotWire.encode(s)) == s)
    }

    @Test func roundTripsAllOptionalsNil() throws {
        let s = HubSnapshot(verdictWord: "—", verdictSession: "", verdictTone: "muted", verdictDate: nil, readiness: nil,
                            kpis: [], fetchedAt: Date(timeIntervalSince1970: 1_791_300_000), lastSync: nil)
        #expect(SnapshotWire.decode(try SnapshotWire.encode(s)) == s)
    }

    @Test func dropsAllKpisWhenOver30KB() throws {
        let big = (0..<600).map { SnapshotKPI(id: .steps, label: "Steps long label \($0) " + String(repeating: "x", count: 40), value: Double($0), unit: "steps") }
        let s = Self.full(allKpis: big)
        #expect(try JSONEncoder().encode(s).count > SnapshotWire.maxBytes)
        let data = try SnapshotWire.encode(s)
        #expect(data.count <= SnapshotWire.maxBytes)
        let back = try #require(SnapshotWire.decode(data))
        #expect(back.allKpis == nil)
        #expect(back.verdictWord == s.verdictWord)
        #expect(back.kpis == s.kpis)
    }

    @Test func keepsAllKpisUnder30KB() throws {
        let s = Self.full()
        #expect(SnapshotWire.decode(try SnapshotWire.encode(s))?.allKpis == s.allKpis)
    }

    @Test func garbageDecodesToNil() {
        #expect(SnapshotWire.decode(Data("not json".utf8)) == nil)
        #expect(SnapshotWire.decode(Data()) == nil)
    }

    @Test func readsFromApplicationContext() throws {
        let s = Self.full()
        let ctx: [String: Any] = ["strengthPlan": Data("{}".utf8), SnapshotWire.key: try SnapshotWire.encode(s)]
        #expect(SnapshotWire.snapshot(in: ctx) == s)
        #expect(SnapshotWire.snapshot(in: ["strengthPlan": Data()]) == nil)
    }
}
