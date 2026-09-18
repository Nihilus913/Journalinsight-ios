import Foundation
import JICompute

// W5b-L5 (P-weekly-plan). Port of `mobile/src/lib/weeklyPlan.ts` — weekly calorie banking
// (zig-zag): hold the WEEKLY average constant while letting chosen "high" days run a surplus,
// funded by banking on low days. Protein is held constant every day (never cycles down); fat is
// held near its floor; the high-day surplus therefore flows into CARBS (reflux-safe).
//
// The training/rest classification is NOT re-implemented here: it reads `JICompute`'s
// `sessionByWeekday` (the port of `SESSION_BY_WEEKDAY`, `MorningGateConfig.swift`), the same
// table the RN oracle imports from `src/compute/morningGate/config.ts`.
//
// `nonisolated` throughout: JIFeatures defaults to `MainActor` isolation, and this is pure value
// math the tests (and any lane) must be able to call off the main actor.

/// `WEEK_DAYS` — Monday-first, the Python `date.weekday()` order `sessionByWeekday` is keyed by,
/// so `allCases` lines up index-for-index with that table.
public nonisolated enum WeekDay: String, CaseIterable, Sendable, Codable, Equatable {
    case mon = "Mon", tue = "Tue", wed = "Wed", thu = "Thu", fri = "Fri", sat = "Sat", sun = "Sun"

    /// RN renders the raw `"Mon"…"Sun"` strings; the enum's raw value IS that label.
    public var label: String { rawValue }
}

/// `WEEK_DAYS` as an ordered list (the oracle's exported constant).
public nonisolated let weekDays: [WeekDay] = WeekDay.allCases

/// JavaScript's `Math.round` — half rounds toward +∞ (Swift's `.rounded()` rounds half away from
/// zero, which differs for negative halves). The oracle rounds kcal and carbs with `Math.round`,
/// so the port must round the same way or a banked low-day value could drift by 1 kcal.
nonisolated func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

public nonisolated struct WeeklyPlanInput: Sendable, Equatable {
    /// The weekly average to preserve.
    public var dailyTargetKcal: Double
    /// Which days get the surplus.
    public var highDays: [WeekDay]
    /// kcal added to each high day.
    public var boostKcal: Double
    /// Held constant every day.
    public var proteinG: Double
    /// Held constant every day (near the floor).
    public var fatG: Double

    public init(dailyTargetKcal: Double, highDays: [WeekDay], boostKcal: Double, proteinG: Double, fatG: Double) {
        self.dailyTargetKcal = dailyTargetKcal
        self.highDays = highDays
        self.boostKcal = boostKcal
        self.proteinG = proteinG
        self.fatG = fatG
    }
}

public nonisolated struct DayPlan: Sendable, Equatable, Identifiable {
    public var day: WeekDay
    public var high: Bool
    public var kcal: Int
    public var protein: Double
    public var carbs: Int
    public var fat: Double

    public var id: WeekDay { day }

    public init(day: WeekDay, high: Bool, kcal: Int, protein: Double, carbs: Int, fat: Double) {
        self.day = day; self.high = high; self.kcal = kcal
        self.protein = protein; self.carbs = carbs; self.fat = fat
    }
}

public nonisolated struct WeeklyPlan: Sendable, Equatable {
    public var days: [DayPlan]
    public var weeklyKcal: Int
    /// `=== dailyTargetKcal` when the budget balances.
    public var avgKcal: Int
    public var proteinG: Double
    public var fatG: Double
    /// kcal removed from each low day (negative).
    public var lowDayDelta: Int

    public init(days: [DayPlan], weeklyKcal: Int, avgKcal: Int, proteinG: Double, fatG: Double, lowDayDelta: Int) {
        self.days = days; self.weeklyKcal = weeklyKcal; self.avgKcal = avgKcal
        self.proteinG = proteinG; self.fatG = fatG; self.lowDayDelta = lowDayDelta
    }
}

public nonisolated func computeWeeklyPlan(_ opts: WeeklyPlanInput) -> WeeklyPlan {
    let nHigh = weekDays.filter { opts.highDays.contains($0) }.count
    let nLow = 7 - nHigh
    // Bank the surplus off the low days so the weekly sum is unchanged.
    let lowDelta = (nHigh > 0 && nLow > 0) ? -(opts.boostKcal * Double(nHigh)) / Double(nLow) : 0
    let days: [DayPlan] = weekDays.map { day in
        let high = opts.highDays.contains(day)
        let kcal = jsRound(opts.dailyTargetKcal + (high ? opts.boostKcal : lowDelta))
        // Protein + fat fixed; carbs absorb the rest (never negative).
        let carbs = max(0, jsRound((kcal - opts.proteinG * 4 - opts.fatG * 9) / 4))
        return DayPlan(day: day, high: high, kcal: Int(kcal), protein: opts.proteinG, carbs: Int(carbs), fat: opts.fatG)
    }
    let weeklyKcal = days.reduce(0) { $0 + $1.kcal }
    return WeeklyPlan(
        days: days,
        weeklyKcal: weeklyKcal,
        avgKcal: Int(jsRound(Double(weeklyKcal) / 7)),
        proteinG: opts.proteinG,
        fatG: opts.fatG,
        lowDayDelta: Int(jsRound(lowDelta))
    )
}

// MARK: - Periodized macros (E12-8, the ji-periodized-macros idea)
//
// Train-vs-rest day targets instead of a manually-toggled highDays set: "high" days are derived
// from the ACTUAL weekly session schedule (`JICompute.sessionByWeekday`) rather than chosen by
// hand, so the periodized plan always matches what's actually programmed. Reuses
// `computeWeeklyPlan`'s exact banking math — a framing layer on top of it, not a second
// implementation.

/// `sessionByWeekday` is keyed Mon=0…Sun=6 (Python `date.weekday()` convention) — the same order
/// as `WeekDay.allCases`, so the two line up index for index.
public nonisolated func sessionTypeForWeekDay(_ day: WeekDay) -> SessionType {
    sessionByWeekday[weekDays.firstIndex(of: day) ?? 0].type
}

/// "optional" (the parked Day 4 Full Upper slot) counts as rest for planning purposes — it isn't
/// guaranteed to happen, so periodizing as if it will would risk a systematic underfeed on the
/// days it doesn't.
public nonisolated func isTrainingWeekDay(_ day: WeekDay) -> Bool {
    let t = sessionTypeForWeekDay(day)
    return t != .rest && t != .optional
}

public nonisolated let trainingWeekDays: [WeekDay] = weekDays.filter(isTrainingWeekDay)
public nonisolated let restWeekDays: [WeekDay] = weekDays.filter { !isTrainingWeekDay($0) }

public nonisolated struct PeriodizedPlanInput: Sendable, Equatable {
    /// The weekly average to preserve.
    public var weeklyAvgKcal: Double
    /// Target kcal on a training day.
    public var trainKcal: Double
    /// Held constant every day (never cycles down).
    public var proteinG: Double
    /// Held constant every day (near the floor).
    public var fatG: Double

    public init(weeklyAvgKcal: Double, trainKcal: Double, proteinG: Double, fatG: Double) {
        self.weeklyAvgKcal = weeklyAvgKcal; self.trainKcal = trainKcal
        self.proteinG = proteinG; self.fatG = fatG
    }
}

/// TS `interface PeriodizedPlan extends WeeklyPlan` — Swift has no struct inheritance, so the base
/// plan is held as `plan` and its members are forwarded verbatim below.
public nonisolated struct PeriodizedPlan: Sendable, Equatable {
    public var plan: WeeklyPlan
    public var trainDays: [WeekDay]
    public var restDays: [WeekDay]
    public var trainKcal: Int
    public var restKcal: Int

    public var days: [DayPlan] { plan.days }
    public var weeklyKcal: Int { plan.weeklyKcal }
    public var avgKcal: Int { plan.avgKcal }
    public var proteinG: Double { plan.proteinG }
    public var fatG: Double { plan.fatG }
    public var lowDayDelta: Int { plan.lowDayDelta }

    public init(plan: WeeklyPlan, trainDays: [WeekDay], restDays: [WeekDay], trainKcal: Int, restKcal: Int) {
        self.plan = plan; self.trainDays = trainDays; self.restDays = restDays
        self.trainKcal = trainKcal; self.restKcal = restKcal
    }
}

public nonisolated func computePeriodizedPlan(_ opts: PeriodizedPlanInput) -> PeriodizedPlan {
    let plan = computeWeeklyPlan(
        WeeklyPlanInput(
            dailyTargetKcal: opts.weeklyAvgKcal,
            highDays: trainingWeekDays,
            boostKcal: opts.trainKcal - opts.weeklyAvgKcal,
            proteinG: opts.proteinG,
            fatG: opts.fatG
        )
    )
    let trainDay = plan.days.first { $0.high }
    let restDay = plan.days.first { !$0.high }
    return PeriodizedPlan(
        plan: plan,
        trainDays: trainingWeekDays,
        restDays: restWeekDays,
        trainKcal: trainDay?.kcal ?? Int(jsRound(opts.trainKcal)),
        restKcal: restDay?.kcal ?? Int(jsRound(opts.weeklyAvgKcal))
    )
}
