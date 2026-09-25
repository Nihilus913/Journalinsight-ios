import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import JIFeatures

// W-FIX4 L2: PF-04 (one sync-pill rule on Recovery, Training, Energy, Nutrition), PF-05 (Journal
// streak card at AX3), PF-09 (Energy "How we calculate" lineage), PF-13 (Readiness date).

private func source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - PF-04

@Test @MainActor func pf04_thePillIsTheNewerOfTheShellTimeAndTheUpload() {
    let hub = Date(timeIntervalSince1970: 1_790_300_000)
    let upload = hub.addingTimeInterval(-7_200)
    #expect(oneSyncPillDate(injected: hub, lastUpload: upload) == hub)
    #expect(oneSyncPillDate(injected: upload, lastUpload: hub) == hub)
    #expect(oneSyncPillDate(injected: nil, lastUpload: upload) == upload)
    #expect(oneSyncPillDate(injected: nil, lastUpload: nil) == nil)
    #expect(EnvironmentValues().jiSyncedAt == nil)
}

@Test func pf04_noScreenPillShowsTheFetchTime() throws {
    for file in ["Recovery/RecoveryView.swift", "Training/TrainingHeader.swift",
                 "Energy/EnergyView.swift", "Nutrition/NutritionView.swift"] {
        let body = try source("Sources/JIFeatures/\(file)")
        #expect(!body.contains("SyncedPill(date: model.fetchedAt"), "\(file) still pills the fetch time")
        #expect(!body.contains("SyncedPill(date: fetchedAt"), "\(file) still pills the fetch time")
        #expect(body.contains("OneSyncedPill("), "\(file) does not use the one rule")
    }
}

@Test func pf04_theUploadRecordFeedsThePill() throws {
    let suite = "fix4-l2-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("2026-09-25T12:51:00Z", forKey: "hk.upload.lastSuccess")
    #expect(parseHubTimestamp(defaults.string(forKey: "hk.upload.lastSuccess")) != nil)
}

// MARK: - PF-13

@Test func pf13_theReadinessSubtitleIsAFormattedDate() {
    let en = Locale(identifier: "en_GB")
    #expect(readinessDateText("2026-09-25", locale: en) == "Fri 25 Sep")
    #expect(readinessDateText(nil, locale: en) == "—")
    #expect(readinessDateText("garbage", locale: en) == "—")
    #expect(gateDetailDateLine(verdictDate: "2026-09-25", isStale: false, locale: en) == "Readiness · Fri 25 Sep")
    #expect(gateDetailDateLine(verdictDate: "2026-09-24", isStale: true, locale: en) == "Readiness from Thu 24 Sep")
}

// MARK: - PF-09

@Test func pf09_energyExplainerNamesTheTrueIntakeSource() throws {
    let eaten = energyHowWeCalculateSteps[1]
    #expect(eaten.title.contains("YAZIO"))
    #expect(!eaten.title.contains("Apple Health"))
    #expect(!eaten.body.contains("Apple Health"))
    #expect(!energyHowWeCalculateSteps.map(\.body).joined().contains("no food in Health"))
    #expect(energyHowWeCalculateSteps.count == JIExplainers.energyBalanceSteps.count)
    let view = try source("Sources/JIFeatures/Energy/EnergyView.swift")
    #expect(view.contains("steps: energyHowWeCalculateSteps"))
}

// MARK: - PF-05

#if canImport(UIKit)
@Test @MainActor func pf05_theWeekDotsRowFitsTheCardAtAX3() {
    let dots = (0..<7).map { i in
        JournalWeekDot(id: "2026-09-2\(i)", initial: ["M", "T", "W", "T", "F", "S", "S"][i],
                       written: i < 2, isToday: i == 4, isFuture: i > 4)
    }
    // iPhone 18 Pro portrait (402 pt) minus the inset-grouped list margins and row padding.
    let width: CGFloat = 402 - 2 * 20 - 2 * 20
    for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
        let host = UIHostingController(rootView: JournalWeekDotsRow(dots: dots).environment(\.dynamicTypeSize, size))
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        #expect(fitted.width <= width + 0.5, "\(size): the week row is \(fitted.width) pt wide in a \(width) pt card")
    }
}
#endif
