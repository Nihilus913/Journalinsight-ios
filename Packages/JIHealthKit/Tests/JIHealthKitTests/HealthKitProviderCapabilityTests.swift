#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

/// W7-L3: the capability seam. Every `HealthDataProvider` method whose domain flag is absent must
/// refuse with `ProviderError.notCapable`, never with an empty/zeroed answer (XC `CLAUDE.md`
/// rule 5) — and the gate trio refuses unconditionally, because the per-source median+MAD
/// baseline it needs is not ported (memory `project_source_agnostic_gate`, `docs/BACKLOG.md`).
@Suite struct HealthKitProviderCapabilityTests {
    private func provider(_ capabilities: DataCapability) -> HealthKitProvider {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let fixed = Date(timeIntervalSince1970: 1_789_000_000)
        return HealthKitProvider(store: FakeHealthStoreReader(), capabilities: capabilities, calendar: cal, now: { fixed })
    }

    /// One row per capability-gated method: the flag it guards, and the call.
    private struct Row: Sendable {
        let name: String
        let capability: DataCapability
        let call: @Sendable (HealthKitProvider) async throws -> Void
    }

    private static let rows: [Row] = [
        Row(name: "recovery", capability: .recovery) { _ = try await $0.recovery(windowDays: 7) },
        Row(name: "syncStatus", capability: .sync) { _ = try await $0.syncStatus() },
    ]

    /// Table-driven: strip exactly one flag out of the full Apple bitmap and the method that
    /// reads it must throw `notCapable` naming that same flag; leave it in and the call succeeds.
    @Test func everyGatedMethodRefusesWhenItsCapabilityIsAbsent() async throws {
        for row in Self.rows {
            let without = provider(DataCapability.appleWatchCapabilities.subtracting(row.capability))
            await #expect(throws: ProviderError.notCapable(row.capability), "\(row.name) must refuse without \(row.capability.rawValue)") {
                try await row.call(without)
            }
            let with = provider(.appleWatchCapabilities)
            await #expect(throws: Never.self, "\(row.name) must answer when capable") {
                try await row.call(with)
            }
        }
    }

    /// Capability-gated OFF: these three throw whatever the bitmap says, because the reason is a
    /// missing baseline store, not a missing HealthKit type. Flipping them on is a BACKLOG row
    /// behind the overnight-equivalence proof (spec risk table L276), not an edit here.
    @Test func theGateTrioIsOffEvenThoughTheBitmapClaimsIt() async throws {
        let p = provider(.appleWatchCapabilities)
        #expect(p.capabilities.contains(.gate))
        #expect(p.capabilities.contains(.morning))
        #expect(p.capabilities.contains(.morningVerdict))
        await #expect(throws: ProviderError.notCapable(.gate)) { _ = try await p.gate(windowDays: 7) }
        await #expect(throws: ProviderError.notCapable(.gate)) { _ = try await p.morning() }
        await #expect(throws: ProviderError.notCapable(.gate)) { _ = try await p.morningVerdict(date: "2026-09-18") }
    }

    @Test func defaultCapabilitiesAreTheFrozenAppleWatchBitmap() {
        let p = HealthKitProvider(store: FakeHealthStoreReader())
        #expect(p.capabilities == DataCapability.appleWatchCapabilities)
    }

    /// The T2 provider is substitutable for the hub one everywhere the app holds the protocol.
    @Test func itIsAHealthDataProvider() {
        let p: any HealthDataProvider = provider(.appleWatchCapabilities)
        #expect(p.capabilities.contains(.recovery))
    }
}

/// W7-L3: the window grid the T2 read runs over.
@Suite struct HealthKitProviderWindowTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func theWindowEndsOnTheDayContainingNow() {
        let w = HKSampleWindow(windowDays: 3, now: date(2026, 9, 18), calendar: calendar)
        #expect(w.days == ["2026-09-16", "2026-09-17", "2026-09-18"])
        #expect(w.start == calendar.startOfDay(for: date(2026, 9, 16)))
        #expect(w.end == calendar.startOfDay(for: date(2026, 9, 19)))
    }

    @Test func aZeroOrNegativeWindowStillHasToday() {
        #expect(HKSampleWindow(windowDays: 0, now: date(2026, 9, 18), calendar: calendar).days == ["2026-09-18"])
        #expect(HKSampleWindow(windowDays: -5, now: date(2026, 9, 18), calendar: calendar).days == ["2026-09-18"])
    }

    @Test func boundsAreHalfOpenAtLocalMidnight() {
        let w = HKSampleWindow(windowDays: 2, now: date(2026, 9, 18), calendar: calendar)
        #expect(w.dayKey(for: w.start) == "2026-09-17")
        #expect(w.dayKey(for: w.start.addingTimeInterval(-1)) == nil)
        #expect(w.dayKey(for: w.end.addingTimeInterval(-1)) == "2026-09-18")
        #expect(w.dayKey(for: w.end) == nil)
    }

    @Test func dayKeysCrossMonthAndYearBoundaries() {
        let w = HKSampleWindow(windowDays: 3, now: date(2027, 1, 1), calendar: calendar)
        #expect(w.days == ["2026-12-30", "2026-12-31", "2027-01-01"])
    }

    /// Keys are formatted arithmetically, so a non-Gregorian/locale-heavy `Calendar` identifier
    /// can never leak a different string for the same instant.
    @Test func dayKeyIsZeroPaddedAndLocaleIndependent() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "ar_SA")
        #expect(HKSampleWindow.isoDay(Date(timeIntervalSince1970: 0), calendar: c) == "1970-01-01")
        #expect(HKSampleWindow.isoDay(Date(timeIntervalSince1970: 1_756_684_800), calendar: c) == "2025-09-01")
    }

    /// The window's own time zone decides the bucket — a sample at 23:30 Zurich on the 17th is
    /// the 17th, not the 21:30 UTC instant's day, and a 00:30 Zurich sample is already the 18th.
    @Test func bucketingFollowsTheWindowsTimeZone() {
        let w = HKSampleWindow(windowDays: 3, now: date(2026, 9, 18), calendar: calendar)
        #expect(w.dayKey(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 30))!) == "2026-09-17")
        #expect(w.dayKey(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 0, minute: 30))!) == "2026-09-18")
    }
}
#endif
