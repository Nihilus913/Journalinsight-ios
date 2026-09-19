import Foundation
import Testing
import JICore
@testable import JIHealthKit

@Suite struct BackloadMonthChunkerTests {
    private var zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        zurich.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func splitsIntoCalendarMonthsInOrder() {
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 9, 17))
        let chunks = BackloadMonthChunker.chunks(for: range, resumeFrom: nil)
        #expect(chunks.count == 5) // May(partial), Jun, Jul, Aug, Sep(partial)
        #expect(chunks[0].from == day(2025, 5, 27))
        #expect(chunks[0].to == day(2025, 5, 31))
        #expect(chunks[1].from == day(2025, 6, 1))
        #expect(chunks[1].to == day(2025, 6, 30))
        #expect(chunks.last!.from == day(2025, 9, 1))
        #expect(chunks.last!.to == day(2025, 9, 17))
        // monotonically increasing, no gaps or overlaps
        for i in 1..<chunks.count {
            #expect(zurich.date(byAdding: .day, value: 1, to: chunks[i - 1].to) == chunks[i].from)
        }
    }

    @Test func resumesFromCursor() {
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 9, 17))
        let chunks = BackloadMonthChunker.chunks(for: range, resumeFrom: day(2025, 7, 15))
        #expect(chunks.first?.from == day(2025, 7, 16))
        #expect(chunks.first?.to == day(2025, 7, 31))
    }

    @Test func cursorAtOrPastRangeEndYieldsNoChunks() {
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 9, 17))
        #expect(BackloadMonthChunker.chunks(for: range, resumeFrom: day(2025, 9, 17)).isEmpty)
        #expect(BackloadMonthChunker.chunks(for: range, resumeFrom: day(2025, 12, 1)).isEmpty)
    }

    @Test func singleDayRangeYieldsOneChunk() {
        let range = BackloadRange(from: day(2025, 6, 15), to: day(2025, 6, 15))
        let chunks = BackloadMonthChunker.chunks(for: range, resumeFrom: nil)
        #expect(chunks == [.init(from: day(2025, 6, 15), to: day(2025, 6, 15))])
    }

    // MARK: - Pass kind sets (v2)

    /// The two sets must be disjoint and their union must be exactly the hub's `ALL_KINDS`
    /// (`app/vitals/backload.py`) — every kind name the contract defines, requested exactly once
    /// across the two passes, with the exact server-side spelling (a typo here means the hub
    /// 422s on `parse_kinds`' unknown-kind check).
    @Test func dailyAndDensePassKindsAreDisjointAndCoverTheFullContract() {
        let daily = BackloadMonthChunker.dailyPassKinds
        let dense = BackloadMonthChunker.densePassKinds
        #expect(daily.isDisjoint(with: dense))
        #expect(daily.union(dense) == [
            "sleep", "rhr", "steps", "energy", "vo2max", "workouts", "daily_resp", "daily_spo2",
            "heart_rate", "respiration", "spo2", "hrv_readings", "step_buckets", "stages",
            "floors", "distance", // W9 (HT e7720ff)
        ])
    }

    /// Every genuinely-dense hub kind (`DENSE_KINDS` server-side) must be in the dense pass, not
    /// the daily pass — this is what makes stage bars / dense HR / SpO2 / HRV / step buckets
    /// reachable at all.
    @Test func densePassIncludesEveryServerDenseKind() {
        let serverDenseKinds: Set<String> = ["heart_rate", "respiration", "spo2", "hrv_readings", "step_buckets", "stages"]
        #expect(serverDenseKinds.isSubset(of: BackloadMonthChunker.densePassKinds))
    }

    /// `stages` alone comes back with an empty `sleep[]` (the hub only attaches stage intervals
    /// to a `sleep` entry when `sleep` itself is requested) — `sleep` must ride along with it.
    @Test func densePassBundlesSleepWithStages() {
        #expect(BackloadMonthChunker.densePassKinds.contains("sleep"))
        #expect(BackloadMonthChunker.densePassKinds.contains("stages"))
    }
}
