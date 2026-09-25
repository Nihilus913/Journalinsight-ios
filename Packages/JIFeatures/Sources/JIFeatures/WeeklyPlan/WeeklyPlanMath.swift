import Foundation
import JICompute
import JIDesign

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

/// B-57 W1 fixer: the least a day can be planned at — the protein and fat held every day, with
/// carbs at zero. Both come from the user's own knobs; below this a day's target would have to
/// take away protein or fat (or, with the banking math unbounded, go negative).
public nonisolated func weeklyPlanDayFloorKcal(proteinG: Double, fatG: Double) -> Double {
    proteinG * 4 + fatG * 9
}

/// The highest training-day target the rest days can fund without any of them dropping below
/// `weeklyPlanDayFloorKcal`, with the weekly average held. Whole kcal, rounded down so the week
/// still sums to exactly 7 × the average. `nil` when the schedule has no training or no rest day
/// (nothing is banked, so there is no cap).
public nonisolated func weeklyPlanMaxTrainKcal(weeklyAvgKcal: Double, proteinG: Double, fatG: Double,
                                              trainDays: [WeekDay] = trainingWeekDays) -> Double? {
    let nHigh = weekDays.filter { trainDays.contains($0) }.count
    let nLow = 7 - nHigh
    guard nHigh > 0, nLow > 0 else { return nil }
    let room = max(0, weeklyAvgKcal - weeklyPlanDayFloorKcal(proteinG: proteinG, fatG: fatG))
    return weeklyAvgKcal + (room * Double(nLow) / Double(nHigh)).rounded(.down)
}

/// TS `interface PeriodizedPlan extends WeeklyPlan` — Swift has no struct inheritance, so the base
/// plan is held as `plan` and its members are forwarded verbatim below.
public nonisolated struct PeriodizedPlan: Sendable, Equatable {
    public var plan: WeeklyPlan
    public var trainDays: [WeekDay]
    public var restDays: [WeekDay]
    public var trainKcal: Int
    public var restKcal: Int
    /// True when the requested training-day target was held lower so no rest day drops below
    /// `restFloorKcal` (the screen says so; the target is never silently changed).
    public var trainCapped: Bool
    /// `weeklyPlanDayFloorKcal` for this plan's protein and fat, whole kcal.
    public var restFloorKcal: Int

    public var days: [DayPlan] { plan.days }
    public var weeklyKcal: Int { plan.weeklyKcal }
    public var avgKcal: Int { plan.avgKcal }
    public var proteinG: Double { plan.proteinG }
    public var fatG: Double { plan.fatG }
    public var lowDayDelta: Int { plan.lowDayDelta }

    public init(plan: WeeklyPlan, trainDays: [WeekDay], restDays: [WeekDay], trainKcal: Int, restKcal: Int,
                trainCapped: Bool = false, restFloorKcal: Int = 0) {
        self.plan = plan; self.trainDays = trainDays; self.restDays = restDays
        self.trainKcal = trainKcal; self.restKcal = restKcal
        self.trainCapped = trainCapped; self.restFloorKcal = restFloorKcal
    }
}

public nonisolated func computePeriodizedPlan(_ opts: PeriodizedPlanInput) -> PeriodizedPlan {
    // B-57 W1 fixer (ROOT CAUSE of the "-600" rest day): with 6 training days and 1 rest day the
    // whole weekly surplus was banked off Sunday with no floor (1800 − 6 × 400 = −600). The
    // training-day target is now held at what the rest days can fund.
    let maxTrain = weeklyPlanMaxTrainKcal(weeklyAvgKcal: opts.weeklyAvgKcal, proteinG: opts.proteinG, fatG: opts.fatG)
    let capped = maxTrain.map { opts.trainKcal > $0 } ?? false
    let trainKcal = capped ? maxTrain! : opts.trainKcal
    let plan = computeWeeklyPlan(
        WeeklyPlanInput(
            dailyTargetKcal: opts.weeklyAvgKcal,
            highDays: trainingWeekDays,
            boostKcal: trainKcal - opts.weeklyAvgKcal,
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
        trainKcal: trainDay?.kcal ?? Int(jsRound(trainKcal)),
        restKcal: restDay?.kcal ?? Int(jsRound(opts.weeklyAvgKcal)),
        trainCapped: capped,
        restFloorKcal: Int(jsRound(weeklyPlanDayFloorKcal(proteinG: opts.proteinG, fatG: opts.fatG)))
    )
}

/// The line under the week when the training-day target was held (nil otherwise).
public nonisolated func weeklyPlanCapNote(_ plan: PeriodizedPlan) -> String? {
    guard plan.trainCapped else { return nil }
    let rest = plan.restDays.count == 1 ? "the rest day" : "the rest days"
    return "Training days held at \(plan.trainKcal) kcal: \(rest) can't bank more without dropping below the protein and fat you eat every day (\(plan.restFloorKcal) kcal)."
}

/// B-57 W1 r4: the held training-day target as a board status line (the board has no separate
/// warning box) — `weeklyPlanCapStatusDetail` carries the reason under it.
public nonisolated func weeklyPlanCapStatus(_ plan: PeriodizedPlan) -> WeeklyPlanGoalStatus? {
    guard plan.trainCapped else { return nil }
    return WeeklyPlanGoalStatus(word: "Training days held at \(plan.trainKcal) kcal", role: .reduced, symbolName: "arrow.down")
}

public nonisolated func weeklyPlanCapStatusDetail(_ plan: PeriodizedPlan) -> String? {
    guard plan.trainCapped else { return nil }
    let rest = plan.restDays.count == 1 ? "The rest day can't" : "The rest days can't"
    return "\(rest) bank more without dropping below the protein and fat you eat every day (\(plan.restFloorKcal) kcal)."
}
