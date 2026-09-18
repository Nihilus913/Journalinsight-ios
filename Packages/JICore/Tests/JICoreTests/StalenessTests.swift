import Foundation
import Testing
@testable import JICore

@Suite struct StalenessTests {
    private let t0 = Date(timeIntervalSince1970: 1_758_000_000)

    @Test func floorMatchesTheOracleConstant() {
        // mobile/src/data/queryKeys.ts:71–77 — HUB_QUERY_STALE_TIME_MS = 45_000.
        #expect(Staleness.hubQueryStaleTime == 45)
    }

    @Test func freshJustUnderTheBoundary() {
        #expect(Staleness.isStale(fetchedAt: t0, now: t0.addingTimeInterval(44.999)) == false)
    }

    @Test func staleExactlyAtTheBoundary() {
        // Inclusive: 45 s IS stale, so the floor is a maximum age.
        #expect(Staleness.isStale(fetchedAt: t0, now: t0.addingTimeInterval(45)) == true)
    }

    @Test func staleJustOverTheBoundary() {
        #expect(Staleness.isStale(fetchedAt: t0, now: t0.addingTimeInterval(45.001)) == true)
    }

    @Test func zeroAgeIsFresh() {
        #expect(Staleness.isStale(fetchedAt: t0, now: t0) == false)
    }

    @Test func neverFetchedIsStale() {
        #expect(Staleness.isStale(fetchedAt: nil, now: t0) == true)
    }

    @Test func futureFetchedAtIsFresh() {
        // Clock skew must not be reported as staleness.
        #expect(Staleness.isStale(fetchedAt: t0.addingTimeInterval(10), now: t0) == false)
    }

    @Test func customStaleTimeIsHonoured() {
        #expect(Staleness.isStale(fetchedAt: t0, now: t0.addingTimeInterval(10), staleTime: 5) == true)
        #expect(Staleness.isStale(fetchedAt: t0, now: t0.addingTimeInterval(10), staleTime: 30) == false)
    }

    @Test func sourceCarriesNoAmbientClock() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/JICore/Staleness.swift").standardized
        let source = try String(contentsOf: url, encoding: .utf8)
        // Strip doc comments: the rule is about executable code, and the doc comment names the
        // forbidden APIs on purpose.
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
        #expect(code.contains("Date()") == false)
        #expect(code.contains("Calendar.current") == false)
        #expect(code.contains("TimeZone.current") == false)
    }
}
