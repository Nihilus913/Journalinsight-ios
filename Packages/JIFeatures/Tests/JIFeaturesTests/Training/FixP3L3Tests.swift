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

    // MARK: RG-62 — Time in zone: friendly errors, spinner on span change, scope, 5 floors, AX labels

    @Test func rg62ErrorsAreFriendlyNeverRawSwift() {
        let offline = zoneTimeErrorText(HubError.network("The Internet connection appears to be offline."))
        #expect(offline == "Can't reach the hub — check your connection and pull to retry.")
        #expect(zoneTimeErrorText(HubError.unauthorized) == "The hub rejected the token — check Settings › Connection.")
        #expect(zoneTimeErrorText(HubError.http(status: 500, detail: "boom")) == "The hub couldn't build this range (error 500). Try again later.")
        #expect(zoneTimeErrorText(HubError.decoding("keyNotFound(CodingKeys…)")) == "The hub sent data this app can't read — update the app or the hub.")
        #expect(zoneTimeErrorText(URLError(.timedOut)) == "Can't reach the hub — check your connection and pull to retry.")
        for e: any Error in [HubError.decoding("x"), HubError.network("y"), URLError(.timedOut)] {
            #expect(!zoneTimeErrorText(e).contains("HubError"))
            #expect(!zoneTimeErrorText(e).contains("Code="))
        }
    }

    @Test func rg62YourZonesListsAllFiveFloors() {
        #expect(zoneFloorsText([97, 117, 139, 160, 176]) == "Your zones · Z1 97 · Z2 117 · Z3 139 · Z4 160 · Z5 176 bpm")
    }

    @Test func rg62AxisLabelsThinOutAtLargeText() {
        let week = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        #expect(zoneAxisLabels(week, span: .week, accessibility: false) == week)
        #expect(zoneAxisLabels(week, span: .week, accessibility: true) == ["Mon", "Wed", "Fri", "Sun"])
        let month = ["1 Sep", "8 Sep", "15 Sep", "22 Sep", "29 Sep"]
        #expect(zoneAxisLabels(month, span: .month, accessibility: true) == ["1 Sep", "15 Sep", "29 Sep"])
        let six = (0..<26).map { "w\($0)" }
        #expect(zoneAxisLabels(six, span: .sixMonths, accessibility: false).count == 6)
        #expect(zoneAxisLabels(six, span: .sixMonths, accessibility: true).count == 3)
    }

    @MainActor @Test func rg62SpanChangeShowsTheSpinnerNotTheOldSpan() async {
        let fake = ZoneFake()
        let model = ZoneTimeModel(provider: fake, span: .week, today: { DayKey(iso: "2026-10-06")! })
        await model.load()
        guard case .loaded = model.phase else { Issue.record("not loaded"); return }
        model.span = .month
        fake.onCall = { @MainActor in #expect(model.phase == .loading) }
        await model.load()
        #expect(fake.scopes.last == "cardio")
    }

    @MainActor @Test func rg62ScopeIsSelectable() async {
        let fake = ZoneFake()
        let model = ZoneTimeModel(provider: fake, span: .week, today: { DayKey(iso: "2026-10-06")! })
        model.scope = .all
        await model.load()
        #expect(fake.scopes == ["all"])
        #expect(ZoneTimeScope.allCases.map(\.title) == ["Cardio", "All workouts"])
    }
}

@MainActor final class ZoneFake: ZoneTimeProviding {
    var scopes: [String] = []
    var onCall: (@MainActor () -> Void)?
    nonisolated func trainingZones(from: String, to: String, bucket: String, scope: String) async throws -> ZoneTimeRange {
        await MainActor.run {
            scopes.append(scope)
            onCall?()
        }
        return ZoneTimeRange(from: from, to: to, bucket: bucket, scope: scope, floors: [97, 117, 139, 160, 176], hrCapBpm: nil,
                             buckets: [], totals: ZoneTimeTotals(minutes: nil, sessions: 0, sessionsNoHr: 0))
    }
}
