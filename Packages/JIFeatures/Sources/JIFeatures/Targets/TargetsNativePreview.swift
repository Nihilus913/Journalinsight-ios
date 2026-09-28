import SwiftUI
import JICore

// W-TGT L3 — the sweep / gallery fixtures for Settings › Targets and its editor sheet (mocks 01,
// 02). Sample numbers for the screenshot only (not anyone's goals); the sleep goal is left unset
// so the "— h / no goal" face is in the sweep too.
enum TargetsFixtures {
    static let document: TargetsDocument = {
        var d = TargetsDocument()
        d.goals.weight = WeightTarget(baseKg: 82.4, targetKg: 76.5, targetDate: "2026-11-30")
        d.goals.kcal = KcalGoal(goalKcal: 2200, basis: .subtractDeficit(.deficit(kcalPerDay: 450)))
        d.goals.proteinG = 150
        d.goals.stepsDaily = 8500
        d.limits = TargetLimits(hrCapBpm: 168, hrCapConfirmedOn: "2026-09-20",
                                zones: HrZones(anchor: .lthr, anchorBpm: 170, floorsBpm: [110, 128, 145, 160, 171]), avoidZone5: true)
        d.rules[.weekProteinFloor] = 125
        return d
    }()

    static func targets() -> AnyView {
        guard let model = TargetsModel.fixture(document) else { return AnyView(NativeFixtureUnavailable(screen: "Targets")) }
        return AnyView(NativeScreenPreview { NavigationStack { TargetsView(model: model, today: { "2026-09-28" }) } })
    }

    static func editor() -> AnyView {
        AnyView(NativeScreenPreview {
            TargetEditorSheet(subject: .goal(.kcal), document: document,
                              normal: TargetNormalInfo(lastSevenText: "1,690 kcal", normalText: "1,610–1,790")) { _ in }
        })
    }
}
