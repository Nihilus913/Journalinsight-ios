import Testing
import Foundation
import JICore
@testable import JIFeatures

/// W-DECIDE-HYBRID (card `docs/waves/cards/W-DECIDE-HYBRID.md`, mockup BP-10-11-hybrid right phone).
@MainActor
struct DecideHybridTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func strain(status: String = "ok", yesterday: Double? = 47, today: Double? = 12,
                        low: Double? = 30, high: Double? = 55,
                        sessions: [MorningStrain.Session]? = [.init(name: "Outdoor Run", minutes: 48)]) -> MorningStrain {
        MorningStrain(status: status, loadedDays: status == "ok" ? 43 : 12, usualLow: low, usualHigh: high,
                      yesterday: .init(date: "2026-10-11", value: yesterday, sessions: sessions),
                      today: .init(date: "2026-10-12", value: today))
    }

    private func override(_ c: VerdictOverrideChoice) -> VerdictOverride {
        VerdictOverride(date: "2026-10-12", choice: c, reason: nil, session: "")
    }

    // MARK: H-1 — top card

    @Test func h1_callHeaderCarriesTheCallTime() {
        let t = decideCallTime("2026-10-12T05:10:33.123456+02:00", timeZone: berlin)
        #expect(t == "05:10")
        #expect(decideCallHeader(verdictDate: "2026-10-12", isStale: false, today: "2026-10-12", callTime: t)
                == "YOUR CALL FOR TODAY · 05:10")
        // Another day's call keeps naming its own day (no time).
        #expect(decideCallHeader(verdictDate: "2026-10-11", isStale: true, today: "2026-10-12", callTime: t)
                == "LAST CALL · SUN, OCT 11")
        #expect(decideCallTime(nil) == nil)
        #expect(decideCallTime("garbage") == nil)
    }

    @Test func h1_buttonsAndNoPinnedBar() throws {
        #expect(decideGoTitle == "Go with this")
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/JIFeatures/Today/DecideView.swift").standardized, encoding: .utf8)
        #expect(!src.contains(".safeAreaInset("))
        #expect(src.contains("actionRows(actions: actions, showsAdjust: showsAdjust)\n            }\n            .frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(src.contains("\"today.decide.title\""))
    }

    @Test func h1_heroLiftHint() {
        #expect(decideHeroLiftHint(("50 kg", "↑ Bench up")) == "50 kg ↑")
        #expect(decideHeroLiftHint(("50 kg", nil)) == "50 kg")
        #expect(decideHeroLiftHint(nil) == nil)
    }

    // MARK: H-2 — frozen values at the call time

    @Test func h2_droveItShowsTheCallsStoredValues() {
        let stored = [
            GateSignal(key: "hrv", label: "HRV", value: 28.4, unit: "ms", threshold: nil, direction: .min,
                       status: .pass, note: ""),
            GateSignal(key: "recovery", label: "Recovery", value: 72, unit: "", threshold: nil, direction: .min,
                       status: .pass, note: ""),
        ]
        let rows = decideDroveItSignals(stored)
        #expect(rows?.map(\.key) == ["hrv"])
        #expect(rows?.first?.value == 28.4)   // the stored value, whatever the phone reads now
        #expect(decideDroveItSignals(nil) == nil)
        #expect(decideDroveItCaption(callTime: "05:10") == "values at 05:10")
        #expect(decideDroveItCaption(callTime: nil) == nil)
    }

    // MARK: H-3 — before the call

    @Test func h3_beforeTheCallIsYesterdayVsUsualWithNoTarget() {
        let s = decideStrainState(strain: strain(), override: nil, verdict: verdictParts("GO — Strength B"))
        guard case let .before(value, usual, position, caption) = s else { Issue.record("\(s)"); return }
        #expect(value == 47 && usual == 30...55 && position == .inside)
        #expect(caption == "Sun: 48 min Outdoor Run · usual = your middle 50 % of loaded days (120 d).")
        #expect(!caption.contains("Max") && !caption.contains("arget"))
        let above = decideStrainState(strain: strain(yesterday: 70), override: nil, verdict: verdictParts("GO — x"))
        if case let .before(_, _, p, _) = above { #expect(p == .above) } else { Issue.record("not before") }
        let rest = decideStrainState(strain: strain(yesterday: 0, sessions: []), override: nil, verdict: verdictParts("GO — x"))
        if case let .before(_, _, p, c) = rest { #expect(p == .below && c.hasPrefix("Sun: no session")) } else { Issue.record("not before") }
    }

    @Test func h3_calibratingAndMissingNeverShowANumber() {
        let cal = decideStrainState(strain: strain(status: "calibrating", yesterday: nil, today: nil, low: nil, high: nil),
                                    override: nil, verdict: verdictParts("GO — x"))
        #expect(cal == .calibrating(loadedDays: 12, needed: 19, maxToday: nil))
        #expect(decideStrainState(strain: nil, override: nil, verdict: verdictParts("GO — x")) == .unavailable)
    }

    // MARK: H-4 — after the call: max from the decided call only

    @Test func h4_maxTodayFollowsTheDecidedCall() {
        #expect(DecideStrainCeiling.full == 60 && DecideStrainCeiling.modified == 40 && DecideStrainCeiling.rest == 20)
        let go = verdictParts("GO — Strength B")
        #expect(DecideStrainCeiling.maxToday(choice: .accept, verdict: go) == 60)
        #expect(DecideStrainCeiling.maxToday(choice: .full, verdict: go) == 60)
        #expect(DecideStrainCeiling.maxToday(choice: .modified, verdict: go) == 40)
        #expect(DecideStrainCeiling.maxToday(choice: .rest, verdict: go) == 20)
        #expect(DecideStrainCeiling.maxToday(choice: .accept, verdict: verdictParts("MODIFIED (HRV low) — Z2 30min")) == 40)
        #expect(DecideStrainCeiling.maxToday(choice: .accept, verdict: verdictParts("REST — recovery")) == 20)
        #expect(DecideStrainCeiling.maxToday(choice: .accept, verdict: verdictParts("RED — sleep 40")) == 20)
    }

    @Test func h4_afterTheCallIsTodayVsMaxWithRoomLeft() {
        let s = decideStrainState(strain: strain(), override: override(.accept), verdict: verdictParts("GO — Strength B"))
        #expect(s == .after(value: 12, maxToday: 60, roomLeft: 48,
                            caption: "Your call: Go → keep today under 60. A limit, not a goal. Modified → 40 · Rest → 20."))
        let over = decideStrainState(strain: strain(today: 45), override: override(.modified), verdict: verdictParts("GO — x"))
        if case let .after(_, m, room, _) = over { #expect(m == 40 && room == 0) } else { Issue.record("not after") }
    }

    @Test func h4_neverFromReadiness() {
        // The state has no readiness input at all: the same call gives the same max on any morning.
        let a = decideStrainState(strain: strain(), override: override(.full), verdict: verdictParts("MODIFIED (HRV low) — x"))
        let b = decideStrainState(strain: strain(yesterday: 5, low: 1, high: 9), override: override(.full), verdict: verdictParts("RED — x"))
        guard case let .after(_, ma, _, _) = a, case let .after(_, mb, _, _) = b else { Issue.record("not after"); return }
        #expect(ma == 60 && mb == 60)
    }

    @Test func h4_calibratingAfterTheCallStillNamesTheMax() {
        let s = decideStrainState(strain: strain(status: "calibrating", yesterday: nil, today: nil, low: nil, high: nil),
                                  override: override(.rest), verdict: verdictParts("GO — x"))
        #expect(s == .calibrating(loadedDays: 12, needed: 19, maxToday: 20))
    }

    // MARK: contract

    @Test func contractFixtureDecodesStrainAndCallTime() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Fixtures/hub-contract/planning_morning.json").standardized
        let m = try JSON.decoder.decode(MorningResponse.self, from: Data(contentsOf: url))
        #expect(m.verdictComputedAt == "2026-09-12T05:10:00+02:00")
        #expect(m.strain?.usualLow == 19 && m.strain?.usualHigh == 49 && m.strain?.loadedDays == 43)
        #expect(m.strain?.yesterday.sessions?.first == MorningStrain.Session(name: "Outdoor Run", minutes: 48))
        #expect(m.strain?.isCalibrating == false)
    }
}
