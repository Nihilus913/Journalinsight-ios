import Foundation
import SwiftUI
import Testing
import JIDesign
@testable import JIFeatures

/// W-BUG1 BUG1-7 (RG-66 leftover): the six state pairs wrapped at default size with "– Rest"
/// alone on a second line (a ragged gap). The legend is now two balanced lines of three pairs,
/// so nothing is orphaned at default size.
@Suite struct Bug1MonthLegendTests {
    @Test func statesAreTwoBalancedLinesOfThree() {
        let lines = trainingMonthLegendStates.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        for line in lines {
            #expect(line.components(separatedBy: "   ").count == 3, "\(line)")
        }
        #expect(lines.last?.hasSuffix("–\u{00A0}Rest") == true)
        #expect(lines.first?.hasPrefix("●\u{00A0}Done") == true)
    }
}

/// BUG1-7 sim-rendered proof shots (iOS Simulator test runner): the Month legend at default size
/// and the Decide readiness ring at default vs AX3. PNGs go to `BUG1_SHOTS` (TEST_RUNNER_BUG1_SHOTS).
@Suite @MainActor struct Bug1RenderShotsTests {
    func render<V: View>(_ name: String, _ view: V, size: DynamicTypeSize, height: CGFloat) -> CGSize? {
        let r = ImageRenderer(content: view.jiTheme(.native).environment(\.jiOffscreenRender, true)
            .environment(\.dynamicTypeSize, size)
            .frame(width: 402, height: height).background(Color(white: 0.95)))
        r.scale = 3
        guard let img = r.uiImage, let png = img.pngData() else { return nil }
        if let dir = ProcessInfo.processInfo.environment["BUG1_SHOTS"], !dir.isEmpty {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return img.size
    }

    @Test func monthLegendAtDefaultSize() {
        #expect(render("bug1-7-month-legend-default", TrainingMonthLegend(), size: .large, height: 120) != nil)
    }

    @Test func readinessRingDefaultAndAX3() {
        #expect(render("bug1-7-ring-default", DecideReadinessRing(score: 72, nights: 28), size: .large, height: 260) != nil)
        #expect(render("bug1-7-ring-ax3", DecideReadinessRing(score: 72, nights: 28), size: .accessibility3, height: 420) != nil)
    }
}
