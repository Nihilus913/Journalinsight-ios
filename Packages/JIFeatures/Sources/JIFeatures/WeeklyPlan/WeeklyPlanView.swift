import SwiftUI
import JIDesign
import JICore

// W5b-L5 (P-weekly-plan). Port of `mobile/app/weekly-plan.tsx`: four steppers that write through
// on every tap, the train/rest day chips derived from the session schedule, and the seven-row
// day table with the weekly-average footer. Reached from the Nutrition tab's "Weekly kcal /
// macro plan" row (RN's real entry) and from Settings → Preferences.
//
// Rule 6: the `info` role (blue) is the selection/CTA accent — the high-day chips and kcal figures
// are a selection state, not a verdict/band/score, so green is deliberately NOT used here.
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Training days (from your session schedule) eat more; the rest day banks it back — the weekly average, and your deficit, stays fixed.")
                .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("weeklyPlan.info")
            JISectionHeader("Targets")
            knobsCard
            JISectionHeader("The week")
            // §8.1: the seven-day table and the knobs compose side by side in regular width.
            tableCard
            footnote
            if model.hasSaved {
                Text("Saved.").jiFont(.micro).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("weeklyPlan.saved")
            }
        }
    }

    // MARK: knobs

    private var knobsCard: some View {
        Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(WeeklyPlanViewModel.Knob.allCases, id: \.self) { stepperRow($0) }
                Text("Training days (\(model.plan.trainDays.count)) · Rest (\(model.plan.restDays.count))")
                    .jiFont(.micro).textCase(.uppercase).foregroundStyle(theme.color(.muted))
                    .padding(.top, 12)
                dayChips
                Text("Set automatically from your Full Upper / interval / Z2 schedule — not manually chosen.")
                    .jiFont(.micro).foregroundStyle(theme.color(.muted))
            }
        }
    }

    private func stepperRow(_ knob: WeeklyPlanViewModel.Knob) -> some View {
        HStack(spacing: 12) {
            Text(knob.label).jiFont(.subheadline).foregroundStyle(theme.color(.text))
            Spacer()
            circleButton(systemImage: "minus") { model.step(knob, by: -knob.stepSize) }
                .accessibilityLabel("\(knob.label) decrease")
                .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).decrease")
            Text("\(weeklyPlanNumberText(model.value(of: knob))) \(knob.unit)")
                .jiNumeral(.numeralSmall).foregroundStyle(theme.color(.text))
                .frame(minWidth: 88)
                .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).value")
            circleButton(systemImage: "plus") { model.step(knob, by: knob.stepSize) }
                .accessibilityLabel("\(knob.label) increase")
                .accessibilityIdentifier("weeklyPlan.\(knob.rawValue).increase")
        }
        .padding(.vertical, 6)
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(theme.color(.text))
                .frame(width: 36, height: 36)
                .background(theme.color(.control), in: Circle())
        }
        .buttonStyle(.pressableScale)
    }

    private var dayChips: some View {
        // A fixed seven-item week never needs to scroll horizontally; wrapping keeps it legible
        // at the largest dynamic-type sizes.
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
                let isTrain = model.plan.trainDays.contains(day)
                Text(day.label)
                    .jiFont(.caption, weight: .bold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(isTrain ? Color.white : theme.color(.muted))
                    .background(isTrain ? theme.color(.info) : theme.color(.control), in: Capsule())
                    .accessibilityLabel("\(day.label) \(isTrain ? "training day" : "rest day")")
                    .accessibilityIdentifier("weeklyPlan.chip.\(day.rawValue)")
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: table

    private var tableCard: some View {
        Surface(padding: 18) {
            VStack(spacing: 0) {
                headerRow
                Divider().overlay(theme.color(.hairlineNested))
                ForEach(model.plan.days) { dayRow($0) }
                averageRow
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            columnText("Day", width: 48, align: .leading)
            Text("kcal").frame(maxWidth: .infinity, alignment: .trailing)
            columnText("P", width: 50, align: .trailing)
            columnText("C", width: 60, align: .trailing)
            columnText("F", width: 46, align: .trailing)
        }
        .jiFont(.micro, weight: .bold).textCase(.uppercase).foregroundStyle(theme.color(.muted))
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    private func columnText(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text).frame(width: width, alignment: align)
    }

    private func dayRow(_ day: DayPlan) -> some View {
        HStack(spacing: 0) {
            Text(day.day.label)
                .jiFont(.subheadline, weight: day.high ? .heavy : .semibold)
                .foregroundStyle(day.high ? theme.color(.info) : theme.color(.text))
                .frame(width: 48, alignment: .leading)
            Text("\(day.kcal)")
                .jiNumeral(.numeralSmall, weight: .heavy)
                .foregroundStyle(day.high ? theme.color(.info) : theme.color(.text))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(weeklyPlanNumberText(day.protein)).frame(width: 50, alignment: .trailing).foregroundStyle(theme.color(.muted))
            Text("\(day.carbs)").frame(width: 60, alignment: .trailing).foregroundStyle(theme.color(.text))
            Text(weeklyPlanNumberText(day.fat)).frame(width: 46, alignment: .trailing).foregroundStyle(theme.color(.muted))
        }
        .jiFont(.footnote)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.day.label): \(day.kcal) kcal, \(weeklyPlanNumberText(day.protein)) g protein, \(day.carbs) g carbs, \(weeklyPlanNumberText(day.fat)) g fat")
        .accessibilityIdentifier("weeklyPlan.row.\(day.day.rawValue)")
    }

    private var averageRow: some View {
        HStack(spacing: 0) {
            Text("Avg").jiFont(.caption).foregroundStyle(theme.color(.muted)).frame(width: 48, alignment: .leading)
            Text("\(model.plan.avgKcal) kcal ✓")
                .jiNumeral(.numeralSmall, weight: .heavy).foregroundStyle(theme.color(.info))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: 156, height: 1)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly average \(model.plan.avgKcal) kcal")
        .accessibilityIdentifier("weeklyPlan.average")
    }

    private var footnote: some View {
        Text("Protein held \(weeklyPlanNumberText(model.proteinG)) g every day · fat capped \(weeklyPlanNumberText(model.fatG)) g · the training-day surplus becomes reflux-safe carbs (rice, Milchreis, potato, banana, berries — front-loaded). Weekly avg \(model.plan.avgKcal) kcal = your target, so the deficit holds.")
            .jiFont(.micro).foregroundStyle(theme.color(.muted))
            .accessibilityIdentifier("weeklyPlan.footnote")
    }
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

    public init(provider: any NutritionProviding) { goalsProvider = provider as? any EnergyProviding }

    public var body: some View {
        NavigationLink {
            WeeklyPlanView(model: WeeklyPlanViewModel(store: .onDisk, goalsProvider: goalsProvider))
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
