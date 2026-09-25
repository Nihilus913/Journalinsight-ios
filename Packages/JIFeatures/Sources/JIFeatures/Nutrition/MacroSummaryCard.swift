import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MacroSummaryCard.tsx`, trimmed to the fields
/// this port's `NutritionProviding` actually carries — protein/carbs/fat *goals* come from a
/// separate `planning/goals` endpoint the RN oracle reads that this screen's contract does not
/// list, so only the kcal goal renders here this wave). Rule 5: a missing value renders "—", never 0.
public struct MacroSummaryCard: View {
    let day: NutritionDayDetail?
    /// W4-L3 — when set, an edit-goals button (mirrors RN's `EditGoalButton`, L117) pushes
    /// `GoalsSetupView`. `nil` (the default) keeps every existing call site source-compatible and
    /// hides the button (optional-model pattern).
    let goalsSetupModel: GoalsSetupViewModel?
    /// W-FIX3 BUG-34: the device's today, so a past day is titled by its weekday, never "today".
    let today: String?
    /// W-FIX3 BUG-35 / BUG-51: the kcal goal when the day payload has none (week row or goals
    /// document), and the macro goals for the board's "52 / 155 g" bars.
    let kcalGoalFallback: Double?
    let macroGoals: NutritionGoal?
    @State private var showGoalsSetup = false
    @Environment(\.jiTheme) private var theme

    public init(day: NutritionDayDetail?, goalsSetupModel: GoalsSetupViewModel? = nil, today: String? = nil,
                kcalGoalFallback: Double? = nil, macroGoals: NutritionGoal? = nil) {
        self.day = day
        self.goalsSetupModel = goalsSetupModel
        self.today = today
        self.kcalGoalFallback = kcalGoalFallback
        self.macroGoals = macroGoals
    }

    private var goals: NutritionGoal? { macroGoals ?? goalsSetupModel?.goals?.nutrition }
    private var isToday: Bool { guard let day, let today else { return true }; return day.date == today }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(day.map { macroCardTitle(date: $0.date, today: today ?? $0.date) } ?? "Macros")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted)).textCase(.uppercase)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("macro-title")
                    if let goalsSetupModel {
                        Spacer()
                        Button {
                            showGoalsSetup = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit nutrition goals")
                        .accessibilityIdentifier("macro-edit-goals")
                        // Attached locally (an isPresented push) — no need for the enclosing
                        // NavigationStack's own navigationDestination(for:).
                        .navigationDestination(isPresented: $showGoalsSetup) {
                            GoalsSetupView(model: goalsSetupModel)
                        }
                    }
                }
                if let day {
                    kcalHero(day.total)
                    Divider().overlay(theme.color(.hairlineNested))
                    ForEach(macroSummaryRows(day.total, goal: goals), id: \.label) { macroBar($0) }
                } else {
                    Text("No nutrition data yet for this day.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("macro-empty")
                }
            }
        }
    }

    /// Board 2/07 hero: "467 / 1617 kcal" and the status word. The goal shows even before the
    /// first meal ("— / 1739 kcal", BUG-35). AX3: the goal and status wrap under the numeral as
    /// whole words instead of hyphenating ("re-/main-", BUG-33).
    private func kcalHero(_ total: NutritionDayTotal) -> some View {
        let goal = nutritionKcalGoal(dayGoal: total.kcalGoal, weekGoal: kcalGoalFallback, goalsGoal: goals?.kcalGoal)
        let status = macroKcalStatus(kcal: total.kcal, goal: goal, isToday: isToday)
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { kcalNumeral(total.kcal); goalText(goal).fixedSize() }
                VStack(alignment: .leading, spacing: 2) { kcalNumeral(total.kcal); goalText(goal).fixedSize(horizontal: false, vertical: true) }
            }
            Text(status).jiFont(.subheadline, weight: .semibold)
                .foregroundStyle(theme.color(total.kcal == nil || goal == nil ? .muted : nutritionKcalTintRole))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("macro-goal")
        }
        .accessibilityElement(children: .ignore)
        // Oracle `MacroSummaryCard.tsx` L170 names this row "Calories".
        .accessibilityLabel("Calories")
        .accessibilityValue("\(total.kcal.map { "\(nutritionWholeText($0)) kcal" } ?? JIMissingReason.noData.rawValue), \(macroHeroGoalText(goal)), \(status)")
        .accessibilityIdentifier("macro-value-kcal")
    }

    private func kcalNumeral(_ kcal: Double?) -> some View {
        // Verbatim: a LocalizedStringKey interpolation would group it as "1'183" (BUG-51).
        Text(verbatim: nutritionWholeText(kcal))
            .jiNumeral(.numeralDisplay, weight: .heavy)
            .foregroundStyle(theme.color(kcal == nil ? .muted : nutritionKcalTintRole))
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func goalText(_ goal: Double?) -> some View {
        Text(verbatim: macroHeroGoalText(goal)).jiFont(.body).foregroundStyle(theme.color(.muted))
    }

    /// Board 2/07 macro bar: "52 / 155 g" over a bar in the macro's own role (C-d). No goal →
    /// the value alone and no bar (rule 5: never a bar against a guess).
    private func macroBar(_ row: MacroSummaryRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { macroValue(row).fixedSize(); Spacer(minLength: 8); macroLabel(row).fixedSize() }
                VStack(alignment: .leading, spacing: 2) {
                    macroValue(row).fixedSize(horizontal: false, vertical: true)
                    macroLabel(row).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let f = row.fraction {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.color(.nested))
                        Capsule().fill(theme.color(row.role)).frame(width: g.size.width * CGFloat(min(1, max(0, f))))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(row.text)
        .accessibilityIdentifier("macro-value-\(row.label.lowercased())")
    }

    private func macroValue(_ row: MacroSummaryRow) -> some View {
        Text(verbatim: row.text).jiFont(.body, weight: .semibold)
            .foregroundStyle(theme.color(row.text.hasPrefix("—") ? .muted : .text))
    }

    private func macroLabel(_ row: MacroSummaryRow) -> some View {
        Label(row.label, systemImage: "circle.fill").labelStyle(MacroDotLabelStyle(color: theme.color(row.role)))
            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
    }
}

private struct MacroDotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); configuration.title }
    }
}

// MARK: - W-FIX3 pure helpers (BUG-34/35/36/51, C-d)

public nonisolated struct MacroSummaryRow: Equatable, Sendable {
    public let label: String
    public let text: String
    public let role: JIColorRole
    /// value / goal, only when the goal is known.
    public let fraction: Double?
}

/// One rounding rule for every nutrition number (the one My KPIs, KpiDetail and the Meal sheet
/// use): half-away rounding to whole units, plain digits with no locale grouping.
public nonisolated func nutritionWholeText(_ value: Double?) -> String {
    jiValueText(value, decimals: 0)
}

/// A meal item's kcal: "527 kcal", or "— No data".
public nonisolated func mealItemKcalText(_ kcal: Double?) -> String {
    jiValueOrReasonText(kcal, decimals: 0, unit: "kcal")
}

/// The hero's goal half: "/ 1739 kcal", or just "kcal" when no goal is known.
public nonisolated func macroHeroGoalText(_ goal: Double?) -> String {
    guard let goal, goal.isFinite, goal > 0 else { return "kcal" }
    return "/ \(nutritionWholeText(goal)) kcal"
}

/// The day payload's goal wins; then the week row's; then the goals document.
public nonisolated func nutritionKcalGoal(dayGoal: Double?, weekGoal: Double?, goalsGoal: Double?) -> Double? {
    [dayGoal, weekGoal, goalsGoal].lazy.compactMap { $0 }.first { $0.isFinite && $0 > 0 }
}

/// Within this share of the goal a finished day reads "On target".
nonisolated let nutritionOnTargetTolerance = 0.05

/// The hero's status word. Today is still filling in, so it reads "On track" until it passes
/// the goal; a finished day is judged against the goal ± 5 %.
public nonisolated func macroKcalStatus(kcal: Double?, goal: Double?, isToday: Bool) -> String {
    guard let kcal, kcal.isFinite else { return "— \(JIMissingReason.noData.rawValue)" }
    guard let goal, goal.isFinite, goal > 0 else { return "No goal set" }
    if isToday {
        let over = (kcal - goal).rounded()
        return kcal <= goal * (1 + nutritionOnTargetTolerance) ? "On track" : "\(jiNumber(over, 0)) kcal over goal"
    }
    let change = (kcal - goal) / goal
    if abs(change) <= nutritionOnTargetTolerance { return "On target" }
    return change < 0 ? "Below target" : "Over target"
}

/// The three macro bars in the board's order, each in its macro role (C-d).
public nonisolated func macroSummaryRows(_ total: NutritionDayTotal, goal: NutritionGoal?) -> [MacroSummaryRow] {
    func row(_ label: String, _ value: Double?, _ goal: Double?, _ role: JIColorRole) -> MacroSummaryRow {
        guard let value, value.isFinite else {
            return MacroSummaryRow(label: label, text: "— \(JIMissingReason.noData.rawValue)", role: role, fraction: nil)
        }
        if let goal, goal.isFinite, goal > 0 {
            return MacroSummaryRow(label: label, text: "\(nutritionWholeText(value)) / \(nutritionWholeText(goal)) g",
                                   role: role, fraction: value / goal)
        }
        return MacroSummaryRow(label: label, text: "\(nutritionWholeText(value)) g", role: role, fraction: nil)
    }
    return [row("Protein", total.proteinG, goal?.proteinG, .protein),
            row("Carbs", total.carbsG, goal?.carbsG, .carbs),
            row("Fat", total.fatG, goal?.fatG, .fat)]
}

/// Protein against its goal, in the board's words ("Below target").
public nonisolated func nutritionProteinStatus(protein: Double?, goal: Double?) -> String {
    guard let protein, protein.isFinite else { return "— \(JIMissingReason.noData.rawValue)" }
    guard let goal, goal.isFinite, goal > 0 else { return "No goal set" }
    return protein >= goal * (1 - nutritionOnTargetTolerance) ? "On target" : "Below target"
}

private nonisolated let nutritionWeekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
private nonisolated let nutritionMonthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/// ("Wednesday", "24 Sep") for an ISO date, or nil for an unparseable one.
nonisolated func nutritionDayParts(_ iso: String) -> (weekday: String, dayMonth: String)? {
    guard let d = trainingStripDate(iso) else { return nil }
    let c = trainingStripCalendar.dateComponents([.weekday, .day, .month], from: d)
    guard let w = c.weekday, let day = c.day, let m = c.month else { return nil }
    return (nutritionWeekdayNames[w - 1], "\(day) \(nutritionMonthShort[m - 1])")
}

/// The navigation subtitle: "Wednesday · 24 Sep" / "Today · 25 Sep" — never the raw ISO date.
public nonisolated func nutritionSubtitle(selected: String, today: String) -> String {
    guard let p = nutritionDayParts(selected) else { return selected }
    return "\(selected == today ? "Today" : p.weekday) · \(p.dayMonth)"
}

/// The section header over the macro card: "Today" or the selected weekday.
public nonisolated func nutritionSectionTitle(selected: String, today: String) -> String {
    selected == today ? "Today" : (nutritionDayParts(selected)?.weekday ?? selected)
}

/// The macro card's caption: "Macros today" or "Macros · Wednesday".
public nonisolated func macroCardTitle(date: String, today: String) -> String {
    date == today ? "Macros today" : "Macros · \(nutritionDayParts(date)?.weekday ?? date)"
}

/// The week strip's caption under the chips: "Wednesday 24 Sep · 1183 kcal".
public nonisolated func nutritionWeekCaption(date: String, kcal: Double?) -> String {
    let name = nutritionDayParts(date).map { "\($0.weekday) \($0.dayMonth)" } ?? date
    return "\(name) · \(mealItemKcalText(kcal))"
}

/// The day before `selected` in the week payload (the board's "Yesterday" cards), or nil.
public nonisolated func nutritionPreviousDay(week: [NutritionDailyRow], selected: String) -> NutritionDailyRow? {
    guard let d = trainingStripDate(selected),
          let prev = trainingStripCalendar.date(byAdding: .day, value: -1, to: d) else { return nil }
    let iso = trainingStripISO(prev)
    return week.first { $0.date == iso }
}
