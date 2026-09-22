// F3: UIKit does not exist on the macOS host the package tests run on — the whole suite is a
// UIKit rendering harness, so it compiles on the UIKit platforms only.
#if canImport(UIKit)
import Foundation
import SwiftUI
import Testing
import UIKit
import JIDesign
@testable import JIFeatures

/// W9.5-L4 (P-today): rotation evidence without a Simulator.app window (the build host has no
/// Simulator UI, so `simctl` cannot rotate). Renders the real `TodayGrid` through `ImageRenderer`
/// at iPhone 18 Pro's landscape content width (874 − 2×59 safe area − 2×20 `TodayView` padding
/// = 716pt) and portrait width (402 − 40 = 362pt) on the iOS 27 simulator. Asserts the adaptive
/// column arithmetic those widths resolve to, and — when `JI_LANDSCAPE_SHOT` names a file
/// (`TEST_RUNNER_JI_LANDSCAPE_SHOT=… xcodebuild test …`) — writes the landscape PNG there as the
/// card's screenshot artefact.
@Suite struct TodayGridLandscapeRenderTests {
    static let chips: [TodayChip] = [
        TodayChip(id: "hrv", label: "HRV", value: 61, unit: "ms", points: [55, 58, 60, 57, 61, 63, 61], sourceMissing: false),
        TodayChip(id: "rhr", label: "RHR", value: 48, unit: "bpm", points: [50, 49, 49, 48, 47, 48, 48], sourceMissing: false),
        TodayChip(id: "sleep", label: "Sleep", value: 7.4, unit: "h", points: [6.5, 7.1, 7.8, 6.9, 7.4, 7.0, 7.4], sourceMissing: false),
        TodayChip(id: "steps", label: "Steps", value: 8_420, unit: nil, points: [6000, 9100, 7800, 10400, 8420, 7300, 8420], sourceMissing: false),
        TodayChip(id: "kcal", label: "Calories", value: 2_140, unit: "kcal", points: [2000, 2300, 2100, 2250, 2140, 1980, 2140], sourceMissing: false),
        TodayChip(id: "protein", label: "Protein", value: 156, unit: "g", points: [140, 162, 150, 158, 156, 149, 156], sourceMissing: false),
    ]

    static let landscapeContentWidth: CGFloat = 874 - 2 * 59 - 2 * 20
    static let portraitContentWidth: CGFloat = 402 - 2 * 20

    @Test @MainActor func landscapeWidthResolvesToThreePlusColumnsAndRenders() throws {
        let min = todayGridMinimumTileWidth(horizontalSizeClass: .compact)   // an 18 Pro is compact in both orientations
        let landscapeColumns = todayGridColumnCount(availableWidth: Self.landscapeContentWidth, minimumTileWidth: min)
        let portraitColumns = todayGridColumnCount(availableWidth: Self.portraitContentWidth, minimumTileWidth: min)
        #expect(landscapeColumns >= 3)
        #expect(portraitColumns == 2)

        // `ImageRenderer` paints a "not allowed" placeholder for UIKit-backed content, so the grid
        // is hosted in a `UIHostingController` at the landscape safe-area box and rendered through
        // its layer — the same layout pass a rotated window runs.
        let size = CGSize(width: 874 - 2 * 59, height: 402 - 21)
        let grid = TodayGrid(chips: Self.chips, prefs: nil, onSelectKpi: { _ in }, makeDataQualityViewModel: { nil })
            .padding(.horizontal, 20)
            .environment(\.horizontalSizeClass, .compact)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(JIColor.bg)
        let host = UIHostingController(rootView: grid)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // let SwiftUI's lazy grid commit its first layout
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            window.layer.render(in: ctx.cgContext)
        }
        window.isHidden = true
        #expect(abs(image.size.width - size.width) < 1)
        #expect(image.size.height > 0)

        if let path = ProcessInfo.processInfo.environment["JI_LANDSCAPE_SHOT"], !path.isEmpty {
            let data = try #require(image.pngData())
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}

#endif
