import Foundation
import JICore

/// Splits a `BackloadRange` into calendar-month chunks (Europe/Zurich), in order, each ≤ 31 days
/// so a single hub request never exceeds the contract's 92-day cap. `resumeFrom` (the persisted
/// cursor — the last successfully-written day) advances the start past what's already done.
enum BackloadMonthChunker {
    struct Chunk: Sendable, Equatable {
        var from: Date
        var to: Date
    }

    private static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BackloadDateParsing.zurich
        return cal
    }

    static func chunks(for range: BackloadRange, resumeFrom cursor: Date?) -> [Chunk] {
        let cal = zurichCalendar
        var start = range.from
        if let cursor, let next = cal.date(byAdding: .day, value: 1, to: cursor) {
            start = max(start, next)
        }
        guard start <= range.to else { return [] }

        var result: [Chunk] = []
        var cursorDate = start
        while cursorDate <= range.to {
            let comps = cal.dateComponents([.year, .month], from: cursorDate)
            guard let monthStart = cal.date(from: comps),
                  let nextMonthStart = cal.date(byAdding: .month, value: 1, to: monthStart),
                  let monthEnd = cal.date(byAdding: .day, value: -1, to: nextMonthStart) else { break }
            let chunkTo = min(monthEnd, range.to)
            result.append(Chunk(from: cursorDate, to: chunkTo))
            guard let next = cal.date(byAdding: .day, value: 1, to: chunkTo) else { break }
            cursorDate = next
        }
        return result
    }
}
