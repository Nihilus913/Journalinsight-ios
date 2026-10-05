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

/// W-FIX-P2 RG-23/24/25 proof shots, rendered on the simulator: Training cold cache offline (one
/// chip, cold-cache copy), a Today-style header offline (one marker, no "Synced hh:mm"), and the
/// Why-today detail opened from a Decide row offline (title + the row's value). Always renders;
/// writes PNGs only when `JI_RG23_PROOF_DIR` is set (`TEST_RUNNER_JI_RG23_PROOF_DIR=…`).
@Suite struct RG23OfflineProofRenderTests {
#if canImport(UIKit) && !os(watchOS)
    @MainActor private func proofImage(_ view: some View, height: CGFloat = 1700) -> CGImage? {
    // Exactly `ScreenSweepTests.sweepImage`'s route, at the 393 pt iPhone width: a real window
    // (never `makeKeyAndVisible` — no host app here), a run-loop turn and a `CATransaction.flush`
    // so the off-screen layer tree actually has contents, then `drawHierarchy` with a
    // `layer.render` fallback. Skipping any of that is what renders a blank page.
    let bounds = CGRect(x: 0, y: 0, width: 393, height: height)
    let host = UIHostingController(rootView: view.jiTheme(.native).jiRevealAnimations(false))
    host.view.frame = bounds
    host.view.backgroundColor = .systemBackground
    host.traitOverrides.userInterfaceStyle = .dark
    host.traitOverrides.horizontalSizeClass = .compact
    host.traitOverrides.verticalSizeClass = .regular

    let window = UIWindow(frame: bounds)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.isHidden = false

    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    CATransaction.flush()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
        if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) {
            host.view.layer.render(in: ctx.cgContext)
        }
    }
    window.isHidden = true
    window.rootViewController = nil
    return image.cgImage
}
    @MainActor private func writePNG(_ image: CGImage?, to url: URL) {
    guard let image,
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { Issue.record("could not render \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

    private struct DeadHealth: HealthDataProvider {
        let capabilities: DataCapability = .hubAll
        private let inner = MockDataProvider()
        func health() async throws -> HealthResponse { try await inner.health() }
        func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("down") }
        func morning() async throws -> MorningResponse { throw HubError.network("down") }
        func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("down") }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("down") }
        func syncStatus() async throws -> SyncStatus { throw HubError.network("down") }
    }

    @Test @MainActor func offlineFacesRender() async throws {
        let out = ProcessInfo.processInfo.environment["JI_RG23_PROOF_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let out { try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }

        // 1. Training, cold cache, hub down.
        let training = PlanWeekdayFakeProvider()
        training.readsFail = true
        let vm = TrainingViewModel(
            provider: training, healthProvider: DeadHealth(), cache: OfflineCache(db: try AppDatabase.inMemory()),
            strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "rg23.\(UUID().uuidString)")))
        await vm.load()
        #expect(vm.phase == .error(OfflineReadCopy.coldCache))
        let t = proofImage(NavigationStack { TrainingView(model: vm) }.environment(\.jiSyncedAt, nil), height: 900)
        #expect(t != nil)

        // 2. A Today-style header offline: the sync pill and the offline pill side by side as the
        //    screens place them — only the offline pill may draw.
        let now = Date()
        let header = VStack(alignment: .leading, spacing: 12) {
            HStack { Spacer(); SyncedPill(date: now.addingTimeInterval(-3_600), now: now) }
            StalenessBanner(fetchedAt: now.addingTimeInterval(-3_600), hubReachable: false, now: now)
            Text("Today").font(.largeTitle.bold())
        }.padding().environment(\.jiHubOffline, true).environment(\.jiSyncedAt, now.addingTimeInterval(-3_600))
        let h = proofImage(header, height: 300)
        #expect(h != nil)

        // 3. Why-today detail opened from the Decide HRV row, hub down, nothing cached.
        let rationale = GateRationaleViewModel(provider: DeadHealth())
        let seed = DecideSignalRowModel(id: "hrv", label: "HRV (7-day)", value: 22, unit: "ms", decimals: 0, status: .watch, detail: nil)
        let r = proofImage(NavigationStack { GateRationaleView(model: rationale, seed: seed).environment(\.jiOffscreenRender, true) }, height: 900)
        _ = r
        await rationale.load()
        let r2 = proofImage(NavigationStack { GateRationaleView(model: rationale, seed: seed).environment(\.jiOffscreenRender, true) }, height: 900)
        #expect(r2 != nil)

        if let out {
            writePNG(t, to: out.appending(path: "rg23-24-training-coldcache-offline.png"))
            writePNG(h, to: out.appending(path: "rg23-today-header-offline.png"))
            writePNG(r2, to: out.appending(path: "rg25-why-today-offline-from-hrv-row.png"))
        }
    }
#endif
}
