import Foundation
import Testing
import JICore
@testable import JIFeatures

/// RG-34: "Also watching" Garmin tiles from an older night (recovery time 21 Sep, body battery
/// 28 Sep) are marked stale and dated — never presented as last night's value.
@Suite struct RecoveryStaleTilesTests {
    let today = "2026-10-05"

    @Test func recoveryTimeFrom21SepIsStaleAndDated() throws {
        var d = RecoveryDay(date: "2026-09-21"); d.recoveryTimeMin = 1
        var bb = RecoveryDay(date: "2026-09-28"); bb.bodyBatteryMin = 5; bb.bodyBatteryMax = 60
        let rs = recoveryWatchReadings(days: [RecoveryDay(date: today), bb, d], today: today)
        let rt = try #require(rs.first { $0.id == "recoveryTime" })
        #expect(rt.stale)
        #expect(rt.caption.contains(try #require(kpiAsOfLabel(valueDate: "2026-09-21", today: today))))
        let battery = try #require(rs.first { $0.id == "bodyBattery" })
        #expect(battery.stale)
        #expect(battery.caption.hasSuffix(try #require(kpiAsOfLabel(valueDate: "2026-09-28", today: today))))
    }

    @Test func lastNightReadingIsNotStale() throws {
        var d = RecoveryDay(date: today); d.recoveryTimeMin = 540
        let rt = try #require(recoveryWatchReadings(days: [d], today: today).first { $0.id == "recoveryTime" })
        #expect(!rt.stale)
        #expect(rt.caption == "to recover · last night")
    }

    @Test func missingReadingIsNotStale() {
        for r in recoveryWatchReadings(days: [], today: today) { #expect(!r.stale) }
    }
}
