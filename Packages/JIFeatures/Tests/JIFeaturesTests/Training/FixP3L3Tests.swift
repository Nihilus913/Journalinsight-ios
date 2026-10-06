import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX-P3 lane l3 — Training screens polish (RG-61, RG-62, RG-63, RG-66, RG-67, RG-68).
@Suite struct FixP3L3Tests {
    // MARK: RG-68 — Send to Watch "Zone 2" alert = the user's Z2 (gate-settings floors 117/139)

    static let userZones = HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176])

    static func zone2Template(workLo: Int = 100, workHi: Int = 140) -> WorkoutTemplate {
        WorkoutTemplate(templateId: 2, name: "Zone 2 40 min", activity: "running", location: .outdoor, weekdays: [0],
                        steps: [WorkoutStep(purpose: .warmup, seconds: 300, hrLo: 100, hrHi: 140),
                                WorkoutStep(purpose: .work, seconds: 1800, hrLo: workLo, hrHi: workHi),
                                WorkoutStep(purpose: .cooldown, seconds: 300, hrLo: 100, hrHi: 140)],
                        updatedAt: "2026-10-05T00:00:00Z")
    }

    @Test func rg68Zone2TemplateRangeIsTheUsersZone2() {
        #expect(sendToWatchAlertRange(Self.zone2Template(), zones: Self.userZones) == 117...138)
    }

    @Test func rg68Zone2WorkStepsCarryTheUsersZone2AtSendTime() {
        let sent = sendToWatchApplyingZones(Self.zone2Template(), zones: Self.userZones)
        let work = sent.effectiveSegments.flatMap { $0.steps.compactMap(\.cardio) }.filter { $0.purpose == .work }
        #expect(work.map(\.target) == [.hrRange(lo: 117, hi: 138)])
        // warm-up / cool-down keep the template's own easy range
        let warm = sent.effectiveSegments.flatMap { $0.steps.compactMap(\.cardio) }.first { $0.purpose == .warmup }
        #expect(warm?.target == .hrRange(lo: 100, hi: 140))
    }

    @Test func rg68NoZonesKeepsTheTemplateWorkRange() {
        #expect(sendToWatchAlertRange(Self.zone2Template(workLo: 116, workHi: 138), zones: nil) == 116...138)
        #expect(sendToWatchApplyingZones(Self.zone2Template(), zones: nil) == Self.zone2Template())
    }

    @Test func rg68NonZone2TemplateIsUntouched() {
        var t = Self.zone2Template(workLo: 160, workHi: 175)
        t.name = "Norwegian 4×4"
        #expect(sendToWatchApplyingZones(t, zones: Self.userZones) == t)
        #expect(sendToWatchAlertRange(t, zones: Self.userZones) == 160...175)
    }

    @Test func rg68RowLineNamesTheWorkRange() {
        #expect(sendToWatchRowSummary(Self.zone2Template(), zones: Self.userZones) == "40 min · 3 steps · alert 117–138 bpm")
    }
}
