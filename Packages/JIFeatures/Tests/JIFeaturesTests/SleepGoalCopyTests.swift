import Foundation
import Testing
import JICompute
@testable import JIFeatures

/// B-57 W3 S3 (spec §0.3): once the recovery score is live, no screen W3 owns calls 7 h a floor or a
/// gate rule. (`TodayViewModel`'s fixture comment is outside this lane — handed off.)
@Test func noScreenCallsSleepAFloorAnyMore() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JIFeatures")
    let owned = ["Today/DecideView.swift", "Today/TrendsView.swift", "GateRationale", "Recovery", "Kpi", "GateConfig", "Shared"]
    let banned = ["Min sleep for intervals", "Min sleep (interval gate)", "sleep floor", "Sleep floor", "7 h floor", "floor-worded"]
    var hits: [String] = []
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        guard owned.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) else { continue }
        let text = try String(contentsOf: url, encoding: .utf8)
        for b in banned where text.contains(b) { hits.append("\(url.lastPathComponent): \(b)") }
    }
    #expect(hits.isEmpty, "floor wording left: \(hits)")
}

@Test func gateConfigGarminKnobIsNotCalledSleepGoal() {
    #expect(MorningGateOverridableField.minSleepH.label == "Garmin nights: min sleep for intervals")
    #expect(MorningGateOverridableField.minSleepH.group == .recoverySignals)
    #expect(!MorningGateOverridableField.minSleepH.explanation.lowercased().contains("goal"))
}

@Test func gateConfigSleepGoalRowIsReadOnlyAndNotAGateRule() {
    #expect(gateConfigSleepGoalTitle == "Sleep goal")
    #expect(gateConfigSleepGoalValue(MorningGateConfig.default) == "7 h")
    #expect(gateConfigSleepGoalExplanation == "A goal, not a gate rule. Short nights reach the call through the recovery score.")
    // No field of the Sleep group is a stepper any more: the goal row is the whole group.
    #expect(MorningGateOverridableField.allCases.filter { $0.group == .sleep }.isEmpty)
}
