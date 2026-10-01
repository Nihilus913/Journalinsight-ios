import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX11 H2-19 (bug hunt 2026-10-01): "Goal targets — Not mirrored yet" after two delivered
// PUT /planning/targets. Since W-TGT the goals live in the phone's targets document; the old
// goal_targets_mirror copy is never written any more, so the set read nothing.

@Test @MainActor func goalTargetsReadTheTargetsDocument() async throws {
    var doc = TargetsDocument.empty
    doc.goals.weight = WeightTarget(baseKg: 85, targetKg: 74)
    doc.goals.stepsDaily = 12000
    let m = LocalMirrorsViewModel(decisionLog: nil, targetsDocument: { doc })
    await m.load()
    #expect(m.goals?.weight.targetKg == 74)
    #expect(m.goals?.stepsDaily == 12000)
    #expect(localMirrorsSummary(hasGoals: m.goals != nil, targetCount: 0, decisionCount: 0).mirrored == 1)
}

@Test @MainActor func noGoalsInTheDocumentIsStillNothing() async {
    let m = LocalMirrorsViewModel(decisionLog: nil, targetsDocument: { .empty })
    await m.load()
    #expect(m.goals == nil)
}

@Test func aMissingWeightTargetReadsAsADash() {
    #expect(goalTargetsMirrorWeightText(.nan) == "—")
    #expect(goalTargetsMirrorWeightText(74) == "74.0 kg")
}
