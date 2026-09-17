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
}
