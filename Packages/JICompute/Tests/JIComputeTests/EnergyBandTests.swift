import Testing
@testable import JICompute

/// B-73 goldens. Hand-computed (EnergyBand has no Python oracle: it is JI-owned, spec §3.1).
/// The kcal target is always the user's own number (Toby 2026-09-24: personal nutrition
/// parameters are user input, never app-imposed). Every target below is a test value.
@Suite struct EnergyBandTests {
    /// 16..24 Sep. 16 is outside the 7-day window, 19 has no basal, 20 has no food, 24 is today.
    static let mixedWeek: [EnergyBandDay] = [
        .init(date: "2026-09-16", basalKcal: 1800, activeKcal: 5000, intakeKcal: 1000),
        .init(date: "2026-09-17", basalKcal: 1800, activeKcal: 600, intakeKcal: 1900),
        .init(date: "2026-09-18", basalKcal: 1800, activeKcal: 400, intakeKcal: 1700),
        .init(date: "2026-09-19", basalKcal: nil, activeKcal: 500, intakeKcal: 1600),
        .init(date: "2026-09-20", basalKcal: 1800, activeKcal: 500, intakeKcal: nil),
        .init(date: "2026-09-21", basalKcal: 1800, activeKcal: 700, intakeKcal: 2000),
        .init(date: "2026-09-22", basalKcal: 1800, activeKcal: 500, intakeKcal: 1800),
        .init(date: "2026-09-23", basalKcal: 1800, activeKcal: 300, intakeKcal: 1400),
        .init(date: "2026-09-24", basalKcal: 900, activeKcal: 100, intakeKcal: 400),
    ]

    static func flat(_ range: ClosedRange<Int>, basal: Double? = 1500, active: Double? = 500, intake: Double? = 2000) -> [EnergyBandDay] {
        range.map { EnergyBandDay(date: "2026-09-\($0)", basalKcal: basal, activeKcal: active, intakeKcal: intake) }
    }

    @Test func completeDayFilterGolden() {
        let r = EnergyBand.compute(targetKcal: 1800, days: Self.mixedWeek, today: "2026-09-24")
        #expect(r.burn.completeDays == 6)     // 17,18,20,21,22,23 — 19 lacks basal, 16 is outside, 24 is today
        #expect(r.burnKcal == 2300)           // 13800 / 6
        #expect(r.burn.basalKcal == 1800)
        #expect(r.burn.activeKcal == 500)     // 3000 / 6
        #expect(r.targetKcal == 1800)
        #expect((r.bandLowKcal, r.bandHighKcal) == (1700, 1900))
        #expect(r.impliedDeficitKcal == 500)  // information only: burn − target
        #expect(r.settled == false)           // 6 of 7
        #expect(r.balanceDays == 5)           // 20 has no food → skipped
        #expect(r.balanceKcal == -540)        // (-500·4 − 700) / 5
        #expect(r.balanceClass == .onPlan)    // target balance = 1800 − 2300 = −500 → −600…−400
    }

    /// The band is target ± 100. It never subtracts anything itself: a goal that already
    /// includes the user's deficit (1600) gives 1500–1700, not 1100 ± 100.
    @Test func bandIsTargetPlusMinus100AndNeverSubtractsAgain() {
        #expect(EnergyBand.band(targetKcal: 1600) == (1500, 1700))
        let r = EnergyBand.compute(targetKcal: 1600, days: Self.flat(21...23), today: "2026-09-24")
        #expect((r.bandLowKcal, r.bandHighKcal) == (1500, 1700))
        #expect(r.impliedDeficitKcal == 400)  // burn 2000 − 1600
    }

    @Test func bandExistsWithoutAnyHealthData() {
        let r = EnergyBand.compute(targetKcal: 1800, days: [], today: "2026-09-24")
        #expect((r.bandLowKcal, r.bandHighKcal) == (1700, 1900))
        #expect(r.calibrating)
        #expect(r.burnKcal == nil)
        #expect(r.impliedDeficitKcal == nil)
        #expect(r.balanceKcal == nil)
        #expect(r.balanceClass == nil)
    }

    @Test func missingBasalEverywhereIsCalibratingButKeepsTheBand() {
        let r = EnergyBand.compute(targetKcal: 1800, days: Self.flat(17...23, basal: nil), today: "2026-09-24")
        #expect(r.calibrating)
        #expect(r.burn.completeDays == 0)
        #expect((r.bandLowKcal, r.bandHighKcal) == (1700, 1900))
    }

    @Test func twoCompleteDaysIsCalibratingThreeIsEnough() {
        func days(_ complete: Int) -> [EnergyBandDay] {
            (17...23).enumerated().map { i, d in
                EnergyBandDay(date: "2026-09-\(d)", basalKcal: i < complete ? 1500 : nil, activeKcal: 500, intakeKcal: 2000)
            }
        }
        let two = EnergyBand.burnWindow(days: days(2), today: "2026-09-24")
        #expect(two.calibrating)
        #expect(two.completeDays == 2)
        #expect(two.burnKcal == nil)
        let three = EnergyBand.burnWindow(days: days(3), today: "2026-09-24")
        #expect(three.completeDays == 3)
        #expect(three.burnKcal == 2000)
        #expect(three.settled == false)
    }

    @Test func sevenCompleteDaysSettleTheBand() {
        #expect(EnergyBand.burnWindow(days: Self.flat(17...23), today: "2026-09-24").settled)
        #expect(!EnergyBand.burnWindow(days: Self.flat(18...23), today: "2026-09-24").settled)
    }

    @Test func targetEqualsBurnGolden() {
        let r = EnergyBand.compute(targetKcal: 2000, days: Self.flat(21...23, intake: 2150), today: "2026-09-24")
        #expect(r.burnKcal == 2000)
        #expect((r.bandLowKcal, r.targetKcal, r.bandHighKcal) == (1900, 2000, 2100))
        #expect(r.impliedDeficitKcal == 0)
        #expect(r.balanceKcal == 150)
        #expect(r.balanceClass == .surplus)
    }

    /// A surplus target is legal (bulk): nothing is clamped.
    @Test func surplusTargetIsLegal() {
        let r = EnergyBand.compute(targetKcal: 2300, days: Self.flat(21...23, intake: 2350), today: "2026-09-24")
        #expect(r.impliedDeficitKcal == -300)
        #expect((r.bandLowKcal, r.bandHighKcal) == (2200, 2400))
        #expect(r.balanceKcal == 350)
        #expect(r.balanceClass == .onPlan)    // target balance +300 → 200…400
    }

    @Test func todayIsExcludedEvenWhenComplete() {
        var days = Self.flat(21...23, intake: 1500)
        days.append(.init(date: "2026-09-24", basalKcal: 9000, activeKcal: 9000, intakeKcal: 100))
        let r = EnergyBand.compute(targetKcal: 1500, days: days, today: "2026-09-24")
        #expect(r.burn.completeDays == 3)
        #expect(r.burnKcal == 2000)
    }

    @Test func noFoodDayIsSkippedNotZero() {
        let days = [
            EnergyBandDay(date: "2026-09-21", basalKcal: 1500, activeKcal: 500, intakeKcal: 1500),
            EnergyBandDay(date: "2026-09-22", basalKcal: 1500, activeKcal: 500, intakeKcal: nil),
            EnergyBandDay(date: "2026-09-23", basalKcal: 1500, activeKcal: 500, intakeKcal: 0),
        ]
        let r = EnergyBand.compute(targetKcal: 1500, days: days, today: "2026-09-24")
        #expect(r.balanceDays == 1)
        #expect(r.balanceKcal == -500)
    }

    @Test func noFoodAnywhereLeavesBalanceNil() {
        let r = EnergyBand.compute(targetKcal: 1500, days: Self.flat(21...23, intake: nil), today: "2026-09-24")
        #expect(r.balanceKcal == nil)
        #expect(r.balanceClass == nil)
        #expect(r.balanceDays == 0)
        #expect(r.burnKcal == 2000)
        #expect((r.bandLowKcal, r.bandHighKcal) == (1400, 1600))
    }

    @Test func zeroActiveIsNotAComplete() {
        let d = EnergyBandDay(date: "2026-09-21", basalKcal: 1500, activeKcal: 0, intakeKcal: 1500)
        #expect(d.burnKcal == nil)
    }

    /// Target balance = target − burn (negative = planned deficit, positive = planned surplus).
    @Test func classifyTable() {
        #expect(EnergyBand.classify(balanceKcal: -500, targetBalanceKcal: -500) == .onPlan)
        #expect(EnergyBand.classify(balanceKcal: -600, targetBalanceKcal: -500) == .onPlan)
        #expect(EnergyBand.classify(balanceKcal: -601, targetBalanceKcal: -500) == .deepDeficit)
        #expect(EnergyBand.classify(balanceKcal: -300, targetBalanceKcal: -500) == .lightDeficit)
        #expect(EnergyBand.classify(balanceKcal: 0, targetBalanceKcal: -500) == .lightDeficit)
        #expect(EnergyBand.classify(balanceKcal: 1, targetBalanceKcal: -500) == .surplus)
        #expect(EnergyBand.classify(balanceKcal: -150, targetBalanceKcal: 0) == .deepDeficit)
        #expect(EnergyBand.classify(balanceKcal: 100, targetBalanceKcal: 0) == .onPlan)
        #expect(EnergyBand.classify(balanceKcal: 100, targetBalanceKcal: 300) == .surplus)      // under a surplus plan, still above burn
        #expect(EnergyBand.classify(balanceKcal: -50, targetBalanceKcal: 300) == .deepDeficit)
    }

    @Test func impliedDeficitCopyRoundsToTen() {
        #expect(EnergyBand.impliedDeficit(burnKcal: 2280, targetKcal: 1800) == 480)
        #expect(EnergyBand.impliedDeficitText(480) == "≈ 480 kcal under what you burn")
        #expect(EnergyBand.impliedDeficitText(484) == "≈ 480 kcal under what you burn")
        #expect(EnergyBand.impliedDeficitText(485) == "≈ 490 kcal under what you burn")
        #expect(EnergyBand.impliedDeficitText(-300) == "≈ 300 kcal over what you burn")
        #expect(EnergyBand.impliedDeficitText(4) == "≈ what you burn")
        #expect(EnergyBand.impliedDeficitText(-4) == "≈ what you burn")
    }

    /// GoalsSetup sanity prompt (subtract-a-deficit goals only; the caller checks the basis).
    @Test func askIfGoalIncludesDeficitTable() {
        // goal 1600 − 500 = 1100 vs burn 2300: gap 1200 > 1000 (and 1600 < 2300 − 300)
        #expect(EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 1600, deficitKcal: 500, burnKcal: 2300))
        // goal 2300 − 500 = 1800: gap 500, goal not below burn − 300 → no prompt
        #expect(!EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 2300, deficitKcal: 500, burnKcal: 2300))
        // goal 2050 is not below 2300 − 300 = 2000, gap 250 → no prompt
        #expect(!EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 2050, deficitKcal: 0, burnKcal: 2300))
        // goal 1950 < 2000 → prompt, even with a zero deficit
        #expect(EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 1950, deficitKcal: 0, burnKcal: 2300))
        // goal above burn but a huge deficit: 2600 − 1500 = 1100, gap 1200 → prompt
        #expect(EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 2600, deficitKcal: 1500, burnKcal: 2300))
        // no burn known → never prompt
        #expect(!EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: 1600, deficitKcal: 500, burnKcal: nil))
    }

    @Test func labelsMatchTheBoard() {
        #expect(EnergyBalanceClass.onPlan.label == "On plan")
        #expect(EnergyBalanceClass.deepDeficit.label == "Deep deficit")
        #expect(EnergyBalanceClass.lightDeficit.label == "Light deficit")
        #expect(EnergyBalanceClass.surplus.label == "Surplus")
    }
    /// PF-03 guard: resting energy (basal) is what turns burn — and so the balance — from null into
    /// a number. The same food week with basal missing stays "Calibrating" with a nil balance; with
    /// basal delivered it yields burn = basal + active and a non-null balance = intake − burn.
    @Test func pf03BasalDeliveryTurnsBalanceNonNull() {
        let noBasal = EnergyBand.compute(targetKcal: 1800, days: Self.flat(17...23, basal: nil, intake: 1800), today: "2026-09-24")
        #expect(noBasal.calibrating)
        #expect(noBasal.burnKcal == nil)
        #expect(noBasal.balanceKcal == nil)
        #expect(noBasal.balanceClass == nil)
        let withBasal = EnergyBand.compute(targetKcal: 1800, days: Self.flat(17...23, basal: 1700, active: 600, intake: 1800), today: "2026-09-24")
        #expect(withBasal.burn.basalKcal == 1700)
        #expect(withBasal.burnKcal == 2300)
        #expect(withBasal.balanceDays == 7)
        #expect(withBasal.balanceKcal == -500)   // intake − burn: negative = deficit (BUG-07 sign)
        #expect(withBasal.balanceClass == .onPlan)
    }
}
