import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import JIDesign
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

// B-33 §8.5: registry × device matrix → one PNG per cell when JI_SWEEP_DIR is set; always
// asserts every entry renders at every size / scheme / type size.

@Test func matrixIsThreeSizesTimesSchemeTimesTypeSize() {
    let cells = SweepMatrix.cells
    #expect(cells.count == 12)
    #expect(Set(cells.map(\.fileStem)).count == 12)
    #expect(cells.contains { $0.width == 956 && $0.height == 440 }) // Pro Max landscape = regular width
}

@Test func registryHasTheGallery() {
    // B-33 phase B: every lane appends its own screens to the registry, so this pins the
    // invariants (gallery first, all native, unique names) instead of the exact list.
    let names = ScreenRegistry.entries.map(\.name)
    #expect(names.first == "Native gallery")
    #expect(Set(names).count == names.count)
    #expect(ScreenRegistry.entries.allSatisfy { $0.theme == .native })
}

#if canImport(UIKit) && !os(watchOS)

/// §8.5 the sweep renders through a real `UIWindow` + `UIHostingController`, not `ImageRenderer`.
/// `ImageRenderer` cannot flatten the UIKit-backed representables behind `List` and
/// `NavigationStack` (it writes the yellow "unrenderable" placeholder and, on some screens,
/// trips `no current update to enqueue action to`), and it derives no size class from
/// `.frame(width:)`, so `AdaptiveHStack` never saw regular width. Trait overrides carry the
/// cell's colour scheme, Dynamic Type size and size class, which `.environment(_:_:)` alone
/// did not deliver to UIKit-backed subviews.
@MainActor
private func sweepImage(_ entry: ScreenEntry, _ cell: SweepCell) -> CGImage? {
    let bounds = CGRect(x: 0, y: 0, width: cell.width, height: cell.height)
    let host = UIHostingController(rootView: entry.make().jiTheme(entry.theme))
    host.view.frame = bounds
    host.view.backgroundColor = .systemBackground

    host.traitOverrides.userInterfaceStyle = cell.dark ? .dark : .light
    host.traitOverrides.preferredContentSizeCategory = cell.ax ? .accessibilityExtraLarge : .large
    // §8.1 regular width is what `AdaptiveHStack` switches on; 956 pt is the regular row.
    host.traitOverrides.horizontalSizeClass = cell.width >= 700 ? .regular : .compact
    host.traitOverrides.verticalSizeClass = cell.height < 500 ? .compact : .regular

    let window = UIWindow(frame: bounds)
    window.overrideUserInterfaceStyle = cell.dark ? .dark : .light
    window.rootViewController = host
    window.isHidden = false
    window.makeKeyAndVisible()

    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    // One turn of the run loop so list/navigation representables commit their first layout.
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()

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

@Test @MainActor func everyRegistryEntryRendersInEveryCell() throws {
    let outDir = ProcessInfo.processInfo.environment["JI_SWEEP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
    for entry in ScreenRegistry.entries {
        for cell in SweepMatrix.cells {
            let image = try #require(sweepImage(entry, cell), "\(entry.name) @ \(cell.fileStem)")
            #expect(image.width == Int(cell.width * 2), "\(entry.name) @ \(cell.fileStem) width")
            if let outDir {
                let url = outDir.appendingPathComponent("\(entry.slug)-\(cell.fileStem).png")
                let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                #expect(CGImageDestinationFinalize(dest), "wrote \(url.lastPathComponent)")
            }
        }
    }
}

/// §8.5 "ax3 reflows": a screen that ignores Dynamic Type renders byte-identically at AX3, which
/// is the failure the verifier caught on every L5 screen. Every entry must differ at AX3.
@Test @MainActor func everyEntryReflowsAtAccessibility3() throws {
    let light = SweepMatrix.cells.filter { !$0.dark && $0.width == 393 }
    let base = try #require(light.first { !$0.ax })
    let ax = try #require(light.first { $0.ax })
    for entry in ScreenRegistry.entries {
        let a = try #require(sweepImage(entry, base).flatMap(pngBytes), entry.name)
        let b = try #require(sweepImage(entry, ax).flatMap(pngBytes), entry.name)
        #expect(a != b, "\(entry.name) renders identically at AX3 — it does not reflow (§8.5)")
    }
}

@MainActor private func pngBytes(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

#endif
