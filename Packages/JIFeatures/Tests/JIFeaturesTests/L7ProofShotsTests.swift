import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import QuartzCore
import JICore
import JIPersistence
import JIDesign
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

// W-FIX-P2 l7 proof shots (RG-33 pace axis, RG-34 stale tiles, RG-35 sleep window). Opt-in:
// `JI_L7_PROOF_DIR` must be set (xcodebuild: TEST_RUNNER_JI_L7_PROOF_DIR), else it returns at once.

#if canImport(UIKit) && !os(watchOS)

nonisolated struct L7ProofProvider: HealthDataProvider, SleepSummaryProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] {
        let today = DayKey.today(now: Date())
        var days = try await inner.recovery(windowDays: windowDays).enumerated().map { i, d -> RecoveryDay in
            var d = d; d.date = today.adding(days: -i).iso; d.recoveryTimeMin = nil; d.bodyBatteryMin = nil; d.bodyBatteryMax = nil
            d.respSleepAvg = 16.4; return d
        }
        var rt = RecoveryDay(date: today.adding(days: -14).iso); rt.recoveryTimeMin = 1
        var bb = RecoveryDay(date: today.adding(days: -7).iso); bb.bodyBatteryMin = 12; bb.bodyBatteryMax = 61
        days.append(contentsOf: [bb, rt])
        return days
    }
    func sleepSummary() async throws -> SleepSummary {
        let today = DayKey.today(now: Date())
        return SleepSummary(lastNightDate: today.iso, lastNightSleepStartLocal: today.adding(days: -1).iso + "T21:13:41",
                            lastNightSleepEndLocal: today.iso + "T04:59:10")
    }
}

@MainActor
private func l7Image(_ view: some View, height: CGFloat) -> CGImage? {
    let bounds = CGRect(x: 0, y: 0, width: 393, height: height)
    let host = UIHostingController(rootView: view.jiTheme(.native).jiRevealAnimations(false))
    host.view.frame = bounds
    host.view.backgroundColor = .systemBackground
    host.traitOverrides.userInterfaceStyle = .dark
    let window = UIWindow(frame: bounds)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.isHidden = false
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    CATransaction.flush()
    let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
    let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
        if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
    }
    window.isHidden = true; window.rootViewController = nil
    return image.cgImage
}

@MainActor
private func l7Write(_ image: CGImage?, _ url: URL) {
    guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { Issue.record("could not render \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

@Suite struct L7ProofShotsTests {
    @Test @MainActor func proofShots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["JI_L7_PROOF_DIR"], !dir.isEmpty else { return }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // RG-33: Runs · Pace with the m:ss axis and avg label (the hub's runs, 543.8 newest).
        let paces: [Double] = [623, 601, 588, 610, 575, 560, 543.8]
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let points = paces.enumerated().map { TrendPoint(date: start.addingTimeInterval(Double($0.offset) * 4 * 86_400), value: $0.element) }
        let chart = VStack(alignment: .leading) {
            Text("Runs · Pace  " + ProgressFormat.value(543.8, metric: .run(.pace))).font(.headline)
            TrendChart(points: points, tint: .primary, unit: "/km", range: .constant(.sixMonths), showAll: nil,
                       valueFormat: ProgressFormat.chartValueFormat(.run(.pace)))
        }.padding()
        l7Write(l7Image(chart, height: 420), out.appendingPathComponent("rg33-pace-axis.png"))

        // RG-34 / RG-35: Recovery with stale Garmin tiles and the served sleep window.
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let model = RecoveryViewModel(provider: L7ProofProvider(), cache: cache)
        await model.load()
        #expect(recoverySleepWindowText(model.sleepSummary) == "21:13–04:59")
        l7Write(l7Image(NavigationStack { ScrollView { RecoveryView(model: model) } }, height: 2600),
                out.appendingPathComponent("rg34-rg35-recovery.png"))
    }
}

#endif
