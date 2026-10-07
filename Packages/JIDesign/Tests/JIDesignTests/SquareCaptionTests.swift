import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import JIDesign

/// W-OFFLINE2 OFF2-3: the Recovery/Today square's status caption no longer truncates — every
/// status word a square shows is within the square's width class (≤ 17 characters, the longest
/// existing word "Below your normal"); the needs-hub square says "Needs the hub".
@Suite struct SquareCaptionTests {
    static let allStatuses: [JISignalStatus] = [
        .aboveGoal, .belowGoal, .onGoal, .inNormal, .belowNormal, .aboveNormal, .clear, .watch, .redFlag,
        .contextOnly, .maintaining, .productive, .overreaching, .paused,
    ] + JIMissingReason.allCases.map { .missing($0) }

    @Test func needsHubSquareWordIsShort() {
        #expect(JISignalStatus.missing(.needsHub).squareWord == "Needs the hub")
        // The full copy stays for VoiceOver and the Today tile caption.
        #expect(JISignalStatus.missing(.needsHub).word == "Garmin value — needs the hub")
    }

    @Test func everySquareWordFitsTheWidthClass() {
        for status in Self.allStatuses {
            #expect(status.squareWord.count <= JISignalStatus.squareWordMaxLength, "\(status.squareWord)")
        }
        #expect(JISignalStatus.missing(.needsHub).word.count > JISignalStatus.squareWordMaxLength)
    }

    @Test func otherSquareWordsUnchanged() {
        for status in Self.allStatuses where status != .missing(.needsHub) {
            #expect(status.squareWord == status.word)
        }
    }

    @Test func accessibilityLabelKeepsTheFullWord() {
        let item = JISquareItem(id: "bodyBattery", label: "Body Battery", value: nil, status: .missing(.needsHub))
        #expect(squareAccessibilityLabel(item).hasSuffix("Garmin value — needs the hub"))
    }

    /// The ImageRenderer shot of the Recovery needs-hub square (dark, 2-column width), written to
    /// `$JI_SHOT_DIR` (default: the temp dir) as `off2-3-recovery-square.png`.
    @MainActor @Test func recoverySquareRenders() throws {
        let row = HStack(spacing: 12) {
            MetricSquare(item: JISquareItem(id: "bodyBattery", label: "Body Battery", systemImage: "bolt.heart",
                                            value: nil, status: .missing(.needsHub)))
            MetricSquare(item: JISquareItem(id: "hrv", label: "HRV", systemImage: "waveform.path.ecg",
                                            value: 44, unit: "ms", status: .inNormal))
        }
        .padding(16).frame(width: 402)
        .jiTheme(.allCases[0]).environment(\.colorScheme, .dark)
        .background(Color.black)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        let dir = ProcessInfo.processInfo.environment["JI_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("off2-3-recovery-square.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("[OFF2-3] shot \(url.path)")
    }
}
