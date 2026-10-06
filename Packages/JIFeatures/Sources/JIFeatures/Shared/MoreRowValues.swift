import SwiftUI
import JICore
import JIDesign

// B-57 W1 r5 (h3): the More tab's trailing values (board `4 Journal & mind/04 More.png`):
// Nutrition "467 / 1617 kcal", Energy "−598 7-day avg vs TDEE", Goals "80.2 → 75.0 kg",
// Mind "WHO-5 62%". Every figure comes from state the app already loads (the Nutrition / Energy /
// Today / Mind models); a missing input is "—" plus a reason word, never an invented number.

/// One trailing value: `lead` is the figure (or "—"), `rest` the muted tail.
public nonisolated struct MoreRowValue: Sendable, Equatable {
    public enum Style: Sendable, Equatable { case kcal, plain, muted }
    public let lead: String
    public let rest: String
    public let style: Style
    public init(lead: String, rest: String, style: Style) { self.lead = lead; self.rest = rest; self.style = style }
    public var text: String { rest.isEmpty ? lead : "\(lead) \(rest)" }

    static func missing(_ reason: String = JIMissingReason.noData.rawValue) -> MoreRowValue {
        MoreRowValue(lead: "—", rest: reason, style: .muted)
    }
}

private nonisolated func kcalInt(_ v: Double?) -> Int? {
    guard let v, v.isFinite else { return nil }
    return Int(v.rounded())
}

/// Nutrition: the logged kcal over the day's goal. No logged kcal → "— No data". W-DATA fixer R1:
/// an earlier day's intake carries its day ("· as of Sep 24"), like the Today Fuel card.
public nonisolated func moreNutritionValue(consumedKcal: Double?, goalKcal: Double?, asOf: String? = nil) -> MoreRowValue {
    guard let consumed = kcalInt(consumedKcal) else { return .missing() }
    let day = asOf.map { " · \($0)" } ?? ""
    // Grouped like every Targets number ("1,617", W-TGT fixer 2 R3).
    let lead = targetsNumber(Double(consumed), 0)
    guard let goal = kcalInt(goalKcal), goal > 0 else { return MoreRowValue(lead: lead, rest: "kcal" + day, style: .kcal) }
    return MoreRowValue(lead: lead, rest: "/ \(targetsNumber(Double(goal), 0)) kcal" + day, style: .kcal)
}

/// W-DATA fixer R1 (DEV-11): today's intake when logged, else the newest logged day of the week
/// (the data exists; the row said "No data" because it only looked at today). nil = nothing logged.
public nonisolated func moreNutritionLatestIntake(today: String, todayKcal: Double?, week: [NutritionDailyRow]) -> (kcal: Double, date: String)? {
    if let todayKcal, todayKcal.isFinite, todayKcal > 0 { return (todayKcal, today) }
    return week.filter { $0.date <= today }.sorted { $0.date > $1.date }
        .first { ($0.kcalConsumed ?? 0) > 0 }.flatMap { r in r.kcalConsumed.map { ($0, r.date) } }
}

/// W-FIX8 M-3: the Energy hero's 7-day balance as a hub-convention deficit (burned − eaten) — the
/// phone's Health band balance (eaten − burned) when it has one, else the hub report's average,
/// gated at `minTrackingDays`. The hero and More › Energy both read this, so they cannot differ.
public nonisolated func energyBalanceDeficit(avgDeficit7d: Double?, trackingDays: Int, bandBalanceKcal: Int?,
                                             minTrackingDays: Int = 4) -> Double? {
    if let b = bandBalanceKcal { return Double(-b) }
    guard trackingDays >= minTrackingDays, let d = avgDeficit7d, d.isFinite else { return nil }
    return d
}

/// Energy: the 7-day average balance vs TDEE — the same numeral and the same source as the Energy
/// hero (`energyBalanceDeficit`: the Health band balance first, else the hub's, 4-day gate).
public nonisolated func moreEnergyValue(avgDeficit7d: Double?, trackingDays: Int, bandBalanceKcal: Int? = nil,
                                        minTrackingDays: Int = 4) -> MoreRowValue {
    guard let d = energyBalanceDeficit(avgDeficit7d: avgDeficit7d, trackingDays: trackingDays, bandBalanceKcal: bandBalanceKcal,
                                       minTrackingDays: minTrackingDays) else { return .missing() }
    return MoreRowValue(lead: energyHeroNumeral(d), rest: "7-day avg vs TDEE", style: .kcal)
}

/// Goals: the latest weight → the goals document's target weight.
/// W-TGT fixer 2 R2: no weight goal but other goals set = "2 goals set", never "No goal set".
public nonisolated func moreGoalsValue(currentKg: Double?, targetKg: Double?, otherGoals: Int = 0) -> MoreRowValue {
    guard let target = targetKg, target.isFinite, target > 0 else {
        guard otherGoals > 0 else { return .missing("No goal set") }
        return MoreRowValue(lead: "\(otherGoals)", rest: otherGoals == 1 ? "goal set" : "goals set", style: .plain)
    }
    let targetText = String(format: "%.1f", target)
    guard let current = currentKg, current.isFinite, current > 0 else {
        return MoreRowValue(lead: "—", rest: "→ \(targetText) kg", style: .muted)
    }
    return MoreRowValue(lead: String(format: "%.1f", current), rest: "→ \(targetText) kg", style: .plain)
}

/// RG-51: the Goals row is the goal's START → goal (the base weight, not today's weight), so it says
/// so and carries the goal's date: "Start 80.2 → goal 75.0 kg · by 31 Oct". The newest weigh-in
/// (My KPIs, e.g. 79.5 on 19 Sep) is a different number and no longer reads as contradicting it.
public nonisolated func moreGoalsStartValue(startKg: Double?, targetKg: Double?, targetDate: String?, otherGoals: Int = 0) -> MoreRowValue {
    guard let target = targetKg, target.isFinite, target > 0 else {
        return moreGoalsValue(currentKg: nil, targetKg: nil, otherGoals: otherGoals)
    }
    let by = targetDate.flatMap { nutritionDayParts($0)?.dayMonth }.map { " · by \($0)" } ?? ""
    let rest = "→ goal \(String(format: "%.1f", target)) kg\(by)"
    guard let start = startKg, start.isFinite, start > 0 else { return MoreRowValue(lead: "—", rest: rest, style: .muted) }
    return MoreRowValue(lead: "Start \(String(format: "%.1f", start))", rest: rest, style: .plain)
}

/// The goals besides the weight goal (daily kcal, protein, carbs, fat, steps) that are set.
public nonisolated func goalsSetCount(_ goals: Goals?) -> Int {
    guard let goals else { return 0 }
    let n = goals.nutrition
    let values: [Double?] = [n.kcalGoal, n.proteinG, n.carbsG, n.fatG, goals.stepsDaily.map(Double.init)]
    return values.filter { v in v.map { $0.isFinite && $0 > 0 } ?? false }.count
}

/// Mind: the latest WHO-5 percentage. None yet → "— No data".
public nonisolated func moreMindValue(who5Pct: Int?) -> MoreRowValue {
    guard let pct = who5Pct else { return MoreRowValue(lead: "WHO-5 —", rest: JIMissingReason.noData.rawValue, style: .muted) }
    return MoreRowValue(lead: "WHO-5 \(pct)%", rest: "", style: .muted)
}

/// The trailing text of a More row: the figure in its role (calorie tint / bold / muted), the tail
/// muted. Wraps at accessibility sizes instead of truncating.
public struct MoreRowTrailing: View {
    let value: MoreRowValue
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ value: MoreRowValue) { self.value = value }

    private var leadColor: Color {
        switch value.style {
        case .kcal: theme.color(nutritionKcalTintRole)
        case .plain: theme.color(.text)
        case .muted: theme.color(.muted)
        }
    }

    public var body: some View {
        let lead = Text(verbatim: value.lead).fontWeight(value.style == .muted ? .regular : .semibold).foregroundStyle(leadColor)
        let rest = Text(verbatim: value.rest.isEmpty ? "" : " \(value.rest)").foregroundStyle(theme.color(.muted))
        Text("\(lead)\(rest)")
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)   // AX sizes stack under the title
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(value.text)
    }
}

/// One More row's label: icon + title leading, the trailing value (`MoreRowTrailing`) after it.
/// The App's More list uses this for every row with a value, so a proof render of it is the row.
public struct MoreRowLabel: View {
    let title: String, systemImage: String, value: MoreRowValue
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ title: String, systemImage: String, value: MoreRowValue) {
        self.title = title; self.systemImage = systemImage; self.value = value
    }
    public var body: some View {
        if typeSize.isAccessibilitySize {
            // W-GUI R-SIM (BUG-33 class): the value drops under the title instead of hyphenating it.
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                MoreRowTrailing(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent { MoreRowTrailing(value) } label: { Label(title, systemImage: systemImage) }
        }
    }
}


/// W-GUI M1 (mockup 08, report §7 rule 6): the More screen's Apple Health row — "Connected" means
/// data ARRIVED (a 2xx upload time), never that iOS reported a permission; no upload yet →
/// "No data yet". Same instant the PF-04 pill uses.
/// W-FIX7: with no upload yet but a Health read on this iPhone (workouts, food) → "Read on iPhone".
public nonisolated func moreAppleHealthText(lastUpload: Date?, readLocally: Bool = false, now: Date = Date(),
                                            calendar: Calendar = .autoupdatingCurrent) -> String {
    guard let lastUpload else { return readLocally ? "Read on iPhone" : "No data yet" }
    let c = calendar.dateComponents([.day, .month, .hour, .minute], from: lastUpload)
    let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    if calendar.isDate(lastUpload, inSameDayAs: now) { return "Connected · last upload \(time)" }
    let months = calendar.shortMonthSymbols
    let month = c.month.map { months[($0 - 1) % months.count] } ?? ""
    return "Connected · last upload \(c.day ?? 0) \(month) \(time)"
}
public nonisolated let moreMirrorCaption = "Values here mirror the screens they open. \u{201C}Connected\u{201D} means data arrived, not that iOS reported a permission."
