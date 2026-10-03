import Foundation
import SwiftUI
import Testing
@testable import JIDesign

/// W-FIX5 L5 — W-GUI-2 S3: the remaining JIDesign components on the F-tokens (report §4.5) and
/// the X2 offline pill (mockup 57).
struct S3ComponentsTests {
    private let t0 = Date(timeIntervalSince1970: 1_758_000_000)

    // MARK: X2 (57) — under a day of the last fetch an unreachable hub is a pill, not a banner

    @Test func offlinePillShowsWithinADayOfTheLastFetchOnlyWhenTheHubIsUnreachable() {
        #expect(offlinePillVisible(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(3_600)))
        #expect(!offlinePillVisible(fetchedAt: t0, hubReachable: true, now: t0.addingTimeInterval(3_600)))
        // Older than a day → the banner takes over (never both).
        #expect(!offlinePillVisible(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(90_000)))
        #expect(stalenessBannerVisible(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(90_000)))
        // Never fetched and unreachable: "Offline" with no time (nothing to invent).
        #expect(offlinePillVisible(fetchedAt: nil, hubReachable: false, now: t0))
    }

    @Test func offlinePillCopyNamesTheLastCallTime() {
        #expect(offlinePillText(lastTime: "07:41") == "Offline · last 07:41")
        #expect(offlinePillText(lastTime: nil) == "Offline")
        #expect(offlinePillAccessibilityLabel(lastTime: "07:41") == "Offline, last synced 07:41")
        #expect(offlinePillAccessibilityLabel(lastTime: nil) == "Offline")
        #expect(stalenessBannerText(lastTime: "07:41") == "Showing data from 07:41 — hub unreachable")
    }

    // MARK: S3 — SignalRow: the label always carries the "your normal —" line slot

    @Test func signalRowReferenceSlotIsNeverEmpty() {
        // No band, no goal, no detail → the slot still says what is missing (rule 5).
        #expect(signalReferenceText(normal: nil, goal: nil, unit: nil, decimals: 0, detail: nil) == "your normal — Calibrating")
        // A caller detail (the hub threshold) still wins over the empty slot.
        #expect(signalReferenceText(normal: nil, goal: nil, unit: "h", decimals: 1, detail: "floor 7.0 h") == "floor 7.0 h")
        #expect(signalRowAccessibilityLabel(label: "Resting HR", value: nil, unit: "bpm", decimals: 0, status: .missing(.noData), reference: "your normal — Calibrating")
                == "Resting HR, no value, No data, your normal — Calibrating")
    }

    // MARK: S3 — every component text goes through the token scale (report §4.5), never a raw `.font(.caption)`

    @Test func s3ComponentsUseTheTypeTokensNotRawFonts() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JIDesign")
        let files = ["SummaryCard", "TrendRow", "StalenessBanner", "DriverBars", "SignalRow", "SkeletonBlock"]
        let raw = try #require(try? NSRegularExpression(pattern: #"\.font\(\.(caption2?|footnote|body|subheadline|headline|title[23]?)[.)]"#))
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent("\(file).swift"), encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // A symbol's size may ride the text style (`Image(systemName:).font(.footnote.weight(...))` — the house chevron idiom).
                guard !line.contains("Image(systemName"), !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                let s = String(line)
                #expect(raw.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil, "\(file).swift:\(n + 1) uses a raw text font: \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    // MARK: render smokes (both themes × both schemes)

    @Test @MainActor func offlinePillAndBannerRender() {
        expectRenders("OfflinePill", height: 60) { OfflinePill(fetchedAt: t0, now: t0.addingTimeInterval(600)) }
        expectRenders("StalenessBanner pill face", height: 60) { StalenessBanner(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(600)) }
        expectRenders("StalenessBanner banner face", height: 80) { StalenessBanner(fetchedAt: t0, hubReachable: false, now: t0.addingTimeInterval(90_000)) }
    }

    @Test @MainActor func tintedSleepCardAndSignalSlotRender() {
        expectRenders("SignalRow calibrating slot", height: 80) { SignalRow(label: "Resting HR", value: 62, unit: "bpm", status: .missing(.calibrating)) }
        expectRenders("DriverBars worded", height: 160) {
            DriverBars(drivers: [DriverBar(id: "a", label: "Sleep", value: 0.7, word: "In your normal", tint: .sleep),
                                 DriverBar(id: "b", label: "HRV", value: nil, word: "Calibrating")])
        }
    }
}
