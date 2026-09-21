import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import JIDesign
@testable import JIFeatures

// B-33 §8.5: registry × device matrix → one PNG per cell when JI_SWEEP_DIR is set; always
// asserts every entry renders at every size / scheme / type size.

@Test func matrixIsThreeSizesTimesSchemeTimesTypeSize() {
    let cells = SweepMatrix.cells
    #expect(cells.count == 12)
    #expect(Set(cells.map(\.fileStem)).count == 12)
    #expect(cells.contains { $0.width == 956 && $0.height == 440 }) // Pro Max landscape = regular width
}

@Test func registryHasTheGallery() {
    #expect(ScreenRegistry.entries.map(\.name) == ["Native gallery"])
    #expect(ScreenRegistry.entries.allSatisfy { $0.theme == .native })
}

@Test @MainActor func everyRegistryEntryRendersInEveryCell() throws {
    let outDir = ProcessInfo.processInfo.environment["JI_SWEEP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
    for entry in ScreenRegistry.entries {
        for cell in SweepMatrix.cells {
            let view = entry.make()
                .frame(width: cell.width, height: cell.height, alignment: .top) // .top: a screen taller than the cell is cut at the fold, never at the header
                .jiTheme(entry.theme)
                .environment(\.colorScheme, cell.dark ? .dark : .light)
                .environment(\.dynamicTypeSize, cell.ax ? .accessibility3 : .large)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "\(entry.name) @ \(cell.fileStem)")
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
