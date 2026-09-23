import Foundation
import Testing
@testable import JIHealthKit

struct HAEPayloadTests {
    @Test func formatsDateWithLocalOffset() {
        let zurich = TimeZone(identifier: "Europe/Zurich")! // +02:00 in September (DST)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 17; comps.hour = 8; comps.minute = 0; comps.second = 0
        comps.timeZone = zurich
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(HAEDate.format(date, timeZone: zurich) == "2026-09-17 08:00:00 +0200")
    }

    @Test func envelopeEncodesQtyPointWithoutSnakeCasing() throws {
        let envelope = HAEEnvelope(metrics: [
            HAEMetric(name: HAEMetricName.stepCount, units: "count", data: [
                HAEDataPoint(date: "2026-09-17 08:00:00 +0200", qty: 120, source: "Apple Watch"),
            ]),
        ])
        let data = try JSONEncoder().encode(envelope)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metrics = try #require(obj["data"] as? [String: Any])
        let metricList = try #require(metrics["metrics"] as? [[String: Any]])
        #expect(metricList.count == 1)
        #expect(metricList[0]["name"] as? String == "step_count")
        let points = try #require(metricList[0]["data"] as? [[String: Any]])
        #expect(points[0]["qty"] as? Double == 120)
        #expect(points[0]["source"] as? String == "Apple Watch")
        #expect(points[0]["sleepEnd"] == nil) // optional fields omitted, not nulled
    }

    @Test func sleepPointKeepsCamelCaseSleepEnd() throws {
        let point = HAEDataPoint(date: "2026-09-17 07:00:00 +0200", sleepEnd: "2026-09-17 07:00:00 +0200", deep: 1.5, core: 3.0, rem: 1.0, awake: 0.5, asleep: 5.5)
        let data = try JSONEncoder().encode(point)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["sleepEnd"] as? String == "2026-09-17 07:00:00 +0200")
        #expect(obj["sleep_end"] == nil)
        #expect(obj["deep"] as? Double == 1.5)
        #expect(obj["qty"] == nil)
    }

    @Test func sleepSegmentsEncodeWithCamelCaseKeys() throws {
        let p = HAEDataPoint(date: "2026-09-23 05:00:00 +0200", sleepEnd: "2026-09-23 05:00:00 +0200",
                             asleep: 7, sleepSegments: [HAESleepSegment(start: "2026-09-22 22:00:00 +0200", end: "2026-09-23 05:00:00 +0200")])
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(json.contains("\"sleepSegments\":[{"))
        #expect(json.contains("\"start\":\"2026-09-22 22:00:00 +0200\""))
        #expect(!json.contains("sleep_segments"))
    }

    @Test func sleepSegmentsOmittedWhenNil() throws {
        let p = HAEDataPoint(date: "2026-09-23 05:00:00 +0200", qty: 1)
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(!json.contains("sleepSegments"))
    }
}
