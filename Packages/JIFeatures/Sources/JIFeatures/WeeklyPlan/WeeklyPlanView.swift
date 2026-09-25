import SwiftUI
import JIDesign
import JICore

// W5b-L5 (P-weekly-plan). Port of `mobile/app/weekly-plan.tsx`: four steppers (saved by "Save
// plan" since B-57 W1 r4), the train/rest day chips derived from the session schedule, and the seven-row
// day table with the weekly-average footer. Reached from the Nutrition tab's "Weekly kcal /
// macro plan" row (RN's real entry) and from Settings → Preferences.
//
// B-57 W1 r4: kcal figures and bars carry the board's calorie tint (`nutritionKcalTintRole`);
// green appears only on the goal status line (a status, rule 6); "Save plan" is the CTA.
public struct WeeklyPlanView: View {
    @State private var model: WeeklyPlanViewModel
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: WeeklyPlanViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        ScrollView {
            nativeContent
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
                .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        .navigationTitle("Weekly plan")
        .task { await model.load() }
    }

    /// §8.5: the composition without the scrolling root — what the sweep renders.
    @ViewBuilder var nativeContent: some View {
        // B-57 W1 board (`3 Plan & train/04 WeeklyPlan.png`): subtitle, the average hero, the week
        // as one bar per day, the legend, then the TARGETS rows. Layout only — every number is
        // the model's, unchanged.
        VStack(alignment: .leading, spacing: 20) {
            Text("Bank weekday calories for a bigger weekend. The weekly deficit stays fixed.")
                .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("weeklyPlan.info")
            VStack(alignment: .leading, spacing: 6) {
                averageHero
                statusLine(model.goalStatus).accessibilityIdentifier("weeklyPlan.goalStatus")
                // C3 amendment (B-73): the plan runs on fallback numbers until the user sets goals.
                if model.usesDefaultGoals {
                    Text(WeeklyPlanViewModel.defaultsDisclaimer).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("weeklyPlan.defaultsDisclaimer")
                }
                // The held training-day target keeps its truth, in the board's status-line form.
                if let held = weeklyPlanCapStatus(model.plan) {
                    statusLine(held).accessibilityIdentifier("weeklyPlan.capNote")
                    if let detail = weeklyPlanCapStatusDetail(model.plan) {
                        Text(detail).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weeklyPlan.capDetail")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                // AX3: "The week" and the training-day count stack instead of truncating.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { weekTitle.fixedSize(); Spacer(minLength: 8); trainDaysText.fixedSize() }
                    VStack(alignment: .leading, spacing: 2) {
                        weekTitle.fixedSize(horizontal: false, vertical: true)
                        trainDaysText.fixedSize(horizontal: false, vertical: true)
                    }
                }
                weekChart
                legend
            }
            VStack(alignment: .leading, spacing: 10) {
                JISectionHeader("Targets")
                targetsCard
                Text(weeklyPlanFootnote)
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("weeklyPlan.footnote")
            }
            VStack(spacing: 6) {
                Button { model.save() } label: {
                    Text("Save plan").jiFont(.body, weight: .semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(theme.color(.info))
                .disabled(!model.canSave)
                .accessibilityIdentifier("weeklyPlan.save")
                if model.hasSaved {
                    Text("Saved.").jiFont(.micro).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("weeklyPlan.saved")
                }
            }
        }
    }

    private func statusLine(_ status: WeeklyPlanGoalStatus) -> some View {
        Label(status.word, systemImage: status.symbolName)
            .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(status.role))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Board hero: the weekly average as the headline figure.
    private var averageHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { heroNumber; heroUnit }
            VStack(alignment: .leading, spacing: 2) { heroNumber; heroUnit }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly average \(model.plan.avgKcal) kcal")
        .accessibilityIdentifier("weeklyPlan.hero")
    }
    private var heroNumber: some View {
        Text(verbatim: weeklyPlanKcalText(model.plan.avgKcal)).jiNumeral(.numeralDisplay, weight: .heavy).foregroundStyle(theme.color(nutritionKcalTintRole))
    }
    private var weekTitle: some View {
        Text("The week").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
    }
    private var trainDaysText: some View {
        Text(weeklyPlanTrainDaysText(model.plan.trainDays.count)).jiFont(.footnote).foregroundStyle(theme.color(.muted))
    }
    private var heroUnit: some View { Text("kcal average").jiFont(.body).foregroundStyle(theme.color(.muted)) }

    // MARK: the week (one bar per day)

    private var weekChart: some View {
        let days = model.plan.days
        let today = weeklyPlanToday()
        return Surface(padding: 16) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    let isToday = day.day == today
                    VStack(spacing: 6) {
                        Text(verbatim: weeklyPlanKcalText(day.kcal))
                            .jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.color(nutritionKcalTintRole).opacity(day.high ? 1 : 0.35))
                            // A planned day always shows its bar (board: rest days are shorter
                            // bars, never absent); the math never plans a day below zero.
                            .frame(height: max(day.kcal > 0 ? 8 : 0, barMaxHeight * weeklyPlanBarFraction(kcal: day.kcal, days: days)))
                        Text(day.day.label)
                            .jiFont(.footnote, weight: isToday ? .bold : .regular)
                            .foregroundStyle(theme.color(isToday ? .text : .muted))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(weeklyPlanDayAccessibilityLabel(day))
                    .accessibilityIdentifier("weeklyPlan.row.\(day.day.rawValue)")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("weeklyPlan.week")
    }

    @ScaledMetric(relativeTo: .body) private var barMaxHeight: CGFloat = 96

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Training day", opacity: 1)
            legendItem("Rest day", opacity: 0.35)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ text: String, opacity: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(theme.color(nutritionKcalTintRole).opacity(opacity)).frame(width: 12, height: 12)
            Text(text).jiFont(.footnote).foregroundStyle(theme.color(.muted))
        }
    }

    // MARK: targets

    private var targetsCard: some View {
        Surface(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(WeeklyPlanViewModel.Knob.allCases.enumerated()), id: \.element) { i, knob in
                    targetRow(knob)
                    if i < WeeklyPlanViewModel.Knob.allCases.count - 1 { Divider().overlay(theme.color(.hairlineNested)) }
                }
            }
        }
    }

    private func targetRow(_ knob: WeeklyPlanViewModel.Knob) -> some View {
        // W-FIX3 BUG-37: the value stays inline with its label (board "Weekly average  1617 kcal").
        // Widest first: label · value · stepper; then label · value with the stepper on its own
        // line; only at AX sizes does the label take its own line so nothing truncates.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                knobLabel(knob).fixedSize()
                Spacer(minLength: 8)
                knobValue(knob).fixedSize()
                knobStepper(knob)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    knobLabel(knob).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    knobValue(knob).fixedSize()
                }
                knobStepper(knob)
            }
            VStack(alignment: .leading, spacing: 8) {
                knobLabel(knob).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) { knobValue(knob).fixedSize(); Spacer(minLength: 8); knobStepper(knob) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func knobLabel(_ knob: WeeklyPlanViewModel.Knob) -> some View {
        Text(knob.label).jiFont(.body).foregroundStyle(theme.color(.text))
    }

    private func knobValue(_ knob: WeeklyPlanViewModel.Knob) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: weeklyPlanTargetText(model.value(of: knob))).jiNumeral(.numeralSmall, weight: .heavy)
                .foregroundStyle(theme.color(weeklyPlanKnobTintRole(knob)))
            Text(knob.unit).jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).value")
    }

    private func knobStepper(_ knob: WeeklyPlanViewModel.Knob) -> some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus") { model.step(knob, by: -knob.stepSize) }
                .accessibilityLabel("\(knob.label) decrease")
                .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).decrease")
            Rectangle().fill(theme.color(.hairlineNested)).frame(width: 1, height: 20)
            stepButton(systemImage: "plus") { model.step(knob, by: knob.stepSize) }
                .accessibilityLabel("\(knob.label) increase")
                .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).increase")
        }
        .background(theme.color(.control), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize()
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.headline).foregroundStyle(theme.color(.text))
                .frame(minWidth: 44, minHeight: 36)
        }
        .buttonStyle(.pressableScale)
    }
}

// MARK: - pure helpers (B-57 W1 board)

/// Board footnote under TARGETS.
public nonisolated let weeklyPlanFootnote = "Carbs fill what is left on each day, and land in the meal after training."

/// B-57 W1 r5: every kcal figure on the screen in one format — plain digits, no locale grouping
/// ("1907", as the board and the TARGETS values show it).
public nonisolated func weeklyPlanKcalText(_ kcal: Int) -> String { String(kcal) }

/// W-FIX3 BUG-37: a TARGETS figure as a whole number ("185", never the raw goals "184.9" /
/// "59.125"), plain digits like every other kcal figure here.
public nonisolated func weeklyPlanTargetText(_ value: Double) -> String {
    value.isFinite ? jiNumber(value, 0) : "—"
}

/// A TARGETS value's tint: the JIDesign macro role for what it measures.
public nonisolated func weeklyPlanKnobTintRole(_ knob: WeeklyPlanViewModel.Knob) -> JIColorRole {
    switch knob {
    case .weeklyAvg, .trainKcal: nutritionKcalTintRole
    case .protein: .protein
    case .fat: .fat
    }
}

/// "The week" header trailing text: the count of training days the schedule sets.
public nonisolated func weeklyPlanTrainDaysText(_ count: Int) -> String {
    count == 1 ? "1 training day" : "\(count) training days"
}

/// A day's bar height as a fraction of the tallest day (0…1). An empty or all-zero week = 0.
public nonisolated func weeklyPlanBarFraction(kcal: Int, days: [DayPlan]) -> CGFloat {
    guard let top = days.map(\.kcal).max(), top > 0 else { return 0 }
    return CGFloat(max(0, kcal)) / CGFloat(top)
}

/// Spelled out for VoiceOver: the day, its kind, and all four numbers the old table showed.
public nonisolated func weeklyPlanDayAccessibilityLabel(_ day: DayPlan) -> String {
    "\(day.day.label), \(day.high ? "training day" : "rest day"): \(day.kcal) kcal, \(weeklyPlanTargetText(day.protein)) g protein, \(day.carbs) g carbs, \(weeklyPlanTargetText(day.fat)) g fat"
}

/// Today's weekday in the plan's Monday-first order.
nonisolated func weeklyPlanToday(_ date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> WeekDay {
    // Calendar weekday: 1 = Sunday … 7 = Saturday.
    let w = calendar.component(.weekday, from: date)
    return weekDays[(w + 5) % 7]
}

// MARK: - Nutrition-tab entry

/// RN `nutrition.tsx:292` — the "Weekly kcal / macro plan" `PressableScale` row under the meal
/// timeline (RN's real entry, NOT Settings). `NutritionView` mounts this in ONE line; it takes the
/// tab's `NutritionProviding` and casts to `EnergyProviding` itself (the hub provider conforms to
/// both — `RootTabView` uses the same cast per tab), so a first-ever visit can seed from the goals
/// document. Persists through `WeeklyPlanStore.onDisk` (see its doc for why).
public struct WeeklyPlanNutritionRow: View {
    private let goalsProvider: (any EnergyProviding)?
    @Environment(\.jiTheme) private var theme
    /// B-57 W2 (B-73): the user's own goals seed the plan before the hub's (nil = not injected).
    @Environment(\.nutritionGoals) private var nutritionGoals

    public init(provider: any NutritionProviding) { goalsProvider = provider as? any EnergyProviding }

    private var jiGoals: (@MainActor () -> MacroGoals?)? {
        guard let macros = nutritionGoals.macros else { return nil }
        return { macros }
    }

    public var body: some View {
        NavigationLink {
            WeeklyPlanView(model: WeeklyPlanViewModel(store: .onDisk, goalsProvider: goalsProvider,
                                                      jiGoals: jiGoals))
        } label: {
            Surface(padding: 18) {
                JIRow(title: "Weekly kcal / macro plan",
                      subtitle: "Bank weekday calories for higher-carb weekends — the deficit stays fixed.",
                      systemImage: "calendar", tint: theme.color(.info)) {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
            }
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("Weekly kcal / macro plan")
        .accessibilityIdentifier("nutrition.row.weeklyPlan")
    }
}
