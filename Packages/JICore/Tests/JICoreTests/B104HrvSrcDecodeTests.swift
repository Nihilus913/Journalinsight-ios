import Foundation
import Testing
@testable import JICore

// B-104 p2: `hrv_src` per recovery-inputs row (HT B-104 p1). Additive — an older hub omits it.

@Test func decodesHrvSrcWhenPresent() throws {
    let json = Data("""
    {"date":"2026-10-04","days":[
      {"date":"2026-09-12","hrv_ms":38.95,"hrv_src":"garmin","rhr_bpm":55},
      {"date":"2026-09-19","hrv_ms":42.1,"hrv_src":"apple"},
      {"date":"2026-09-20","hrv_ms":null,"hrv_src":null}
    ]}
    """.utf8)
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: json)
    #expect(r.days.map(\.hrvSrc) == ["garmin", "apple", nil])
    #expect(r.days.map(\.isGarminHrv) == [true, false, false])
    #expect(r.days.map(\.isWatchHrv) == [false, true, false])
}

@Test func olderHubWithoutHrvSrcReadsAsWatch() throws {
    let json = Data("""
    {"date":"2026-10-04","days":[{"date":"2026-09-19","hrv_ms":42.1,"rhr_bpm":60}]}
    """.utf8)
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: json)
    #expect(r.days[0].hrvSrc == nil)
    #expect(r.days[0].isWatchHrv)
    #expect(!r.days[0].isGarminHrv)
}

@Test func hrvSrcRoundTripsThroughTheCache() throws {
    let day = RecoveryInputDay(date: "2026-09-12", hrvMs: 38.95, hrvSrc: "garmin")
    let back = try JSON.decoder.decode(RecoveryInputDay.self, from: JSON.encoder.encode(day))
    #expect(back == day)
}
