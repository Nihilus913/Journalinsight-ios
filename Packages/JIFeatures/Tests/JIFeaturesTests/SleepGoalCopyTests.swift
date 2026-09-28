import Foundation
import Testing
import JICompute
import JICore
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

/// W-TGT L3: the Garmin interval knob is a Targets rule, never called the sleep goal.
@Test func garminKnobIsARuleNotTheSleepGoal() {
    #expect(targetsRuleTitle(.intervalMinSleep) == "Garmin nights · interval floor")
    #expect(!targetsRuleExplanation(.intervalMinSleep).lowercased().contains("goal"))
}

/// W-TGT L3 (D2): the sleep goal is a Goal the user types — "— h / no goal" until then, never 7 h.
@Test func sleepGoalIsAUserGoalNilUntilTyped() {
    let row = TargetsRows.goals(.empty).first { $0.subject == .goal(.sleep) }
    #expect(row?.value == "— h")
    #expect(row?.subtitle == "no goal")
    var doc = TargetsDocument.empty
    doc.goals.sleepH = 7
    #expect(TargetsRows.goals(doc).first { $0.subject == .goal(.sleep) }?.value == "7.0 h")
    #expect(targetsGoalCaption(.sleep, 7) == "goal 7 h")
}
