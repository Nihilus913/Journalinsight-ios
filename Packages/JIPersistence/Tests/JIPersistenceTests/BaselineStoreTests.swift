import Foundation
import GRDB
import Testing
@testable import JIPersistence

/// W-ONDEVICE O-6 (B-20): the on-device baseline store — raw nightly values only, 120-day
/// retention, recompute-on-read (no median/MAD is ever persisted).
@Suite struct BaselineStoreTests {
    private func day(_ offset: Int, from start: String = "2026-01-01") -> String {
        BaselineStore.addDays(offset, to: start)!
    }

    @Test func migrationCreatesBaselineSampleWithCompositeKey() throws {
        let db = try AppDatabase.inMemory()
        try db.pool.read { conn in
            #expect(try conn.tableExists("baseline_sample"))
            let columns = try conn.columns(in: "baseline_sample").map(\.name)
            #expect(columns == ["source", "metric", "date", "value"])
            let pk = try conn.primaryKey("baseline_sample").columns
            #expect(pk == ["source", "metric", "date"])
        }
    }

    @Test func oneHundredThirtyDaysInOneHundredTwentyKept() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        let rows = (0..<130).map { BaselineSample(source: .apple, metric: .hrvRmssdMs, date: day($0), value: Double(40 + $0 % 7)) }
        let today = day(129)
        try store.record(rows, today: today)
        let kept = try store.series(metric: .hrvRmssdMs, through: today)
        #expect(kept.count == 120)
        #expect(kept.first?.date == day(10))
        #expect(kept.last?.date == today)
    }

    @Test func sameDayTwiceIsOneRowAndTheLatestValueWins() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        let d = "2026-10-03"
        try store.record([BaselineSample(source: .apple, metric: .rhrBpm, date: d, value: 52)], today: d)
        try store.record([BaselineSample(source: .apple, metric: .rhrBpm, date: d, value: 51)], today: d)
        let rows = try store.series(metric: .rhrBpm, through: d)
        #expect(rows == [BaselineSample(source: .apple, metric: .rhrBpm, date: d, value: 51)])
    }

    @Test func sourcesAreKeptApartForTheSameNight() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        let d = "2026-10-03"
        try store.record([
            BaselineSample(source: .apple, metric: .hrvRmssdMs, date: d, value: 38),
            BaselineSample(source: .garmin, metric: .hrvRmssdMs, date: d, value: 45),
        ], today: d)
        #expect(try store.series(metric: .hrvRmssdMs, through: d).count == 2)
        #expect(try store.series(metric: .hrvRmssdMs, source: .apple, through: d).map(\.value) == [38])
        #expect(try store.count(source: .garmin) == 1)
    }

    @Test func readIsBoundedByThroughAndNeverReturnsFutureRows() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        try store.record([
            BaselineSample(source: .apple, metric: .sleepDurationSec, date: "2026-10-02", value: 25_000),
            BaselineSample(source: .apple, metric: .sleepDurationSec, date: "2026-10-04", value: 26_000),
        ], today: "2026-10-04")
        let rows = try store.series(metric: .sleepDurationSec, through: "2026-10-03")
        #expect(rows.map(\.date) == ["2026-10-02"])
    }

    @Test func nonFiniteValuesAreNeverStored() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        try store.record([BaselineSample(source: .apple, metric: .hrvRmssdMs, date: "2026-10-03", value: .nan)], today: "2026-10-03")
        #expect(try store.count(source: .apple) == 0)
    }

    @Test func nightlyGroupsMetricsPerSourceAndDate() throws {
        let store = BaselineStore(db: try AppDatabase.inMemory())
        let d = "2026-10-03"
        try store.record([
            BaselineSample(source: .apple, metric: .hrvRmssdMs, date: d, value: 38),
            BaselineSample(source: .apple, metric: .rhrBpm, date: d, value: 50),
            BaselineSample(source: .garmin, metric: .hrvRmssdMs, date: "2026-10-01", value: 44),
        ], today: d)
        let nights = try store.nightly(through: d)
        #expect(nights.count == 2)
        #expect(nights[0] == BaselineNight(source: .garmin, date: "2026-10-01", values: [.hrvRmssdMs: 44]))
        #expect(nights[1] == BaselineNight(source: .apple, date: d, values: [.hrvRmssdMs: 38, .rhrBpm: 50]))
    }
}
