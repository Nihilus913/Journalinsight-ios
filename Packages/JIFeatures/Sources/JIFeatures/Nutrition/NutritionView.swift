import SwiftUI
import JICore
import JIDesign

/// Nutrition tab (W3a-L2, frozen contract `NutritionView.init(model:)` — mirrors
/// `mobile/app/(tabs)/nutrition.tsx`): week strip → day select → meal timeline + macro card, plus
/// a read-only Meal detail sheet (B-57 W1: JI never logs food). Rule 5 (never render a zero for missing data) and rule 6 (green reserved for
/// verdict/band/score/status) both apply throughout.
public struct NutritionView: View {
    @Bindable private var model: NutritionViewModel
    @State private var selectedMeal: MealDetail?
    /// B-57 W2 (B-73): the user's own goals, injected at the app root (never the hub document).
    @Environment(\.nutritionGoals) private var nutritionGoals
    @Environment(\.dynamicTypeSize) private var typeSize
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: NutritionViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // AX sizes: the navigation subtitle cannot wrap, so the day line moves into the page.
                if typeSize.isAccessibilitySize {
                    Text(subtitle).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutrition-subtitle")
                }
                HStack { Spacer(); OneSyncedPill(label: .lastSynced) }  // W-FIX4 PF-04
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("nutrition-empty")
                case .loaded: loaded
                }
                readOnlyNote
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        // §5: the hand-drawn large title + date line become the system title and subtitle.
        .navigationTitle("Nutrition")
        #if os(iOS)
        // W-FIX3 BUG-34: the selected day in words, never the raw ISO date.
        .navigationSubtitle(typeSize.isAccessibilitySize ? "" : subtitle)
        #endif
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
        .sheet(item: Binding(get: { selectedMeal.map(IdentifiedMeal.init) }, set: { selectedMeal = $0?.detail })) {
            MealDetailSheet(detail: $0.detail)
        }
    }

    private var today: String { energyTodayISO() }
    private var subtitle: String { nutritionSubtitle(selected: model.selectedDate, today: today) }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 60); SkeletonBlock(height: 120); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("nutrition-error")
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("nutrition-retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            NutritionWeekStrip(days: model.week, selectedDate: model.selectedDate) { date in
                Task { await model.selectDate(date) }
            }
            JISectionHeader(nutritionSectionTitle(selected: model.selectedDate, today: today))
            MacroSummaryCard(day: model.day, today: today)
            JISectionHeader("Meals")
            MealTimeline(day: model.day, onSelectMeal: { selectedMeal = $0 })
            if let prev = nutritionPreviousDay(week: model.week, selected: model.selectedDate) {
                NutritionPreviousDayCards(row: prev, isYesterday: model.selectedDate == today,
                                          kcalGoal: nutritionGoals.kcalGoal, proteinGoal: nutritionGoals.goal(for: .protein))
            }
            WeeklyPlanNutritionRow(provider: model.provider) // W5b-L5: RN nutrition.tsx:292 "Weekly kcal / macro plan" row
        }
    }

    private var readOnlyNote: some View {
        Surface(level: 2) {
            Label(nutritionReadOnlyNote, systemImage: "info.circle").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("nutrition-readonly-note")
    }
}

/// Board 2/07 "Yesterday": the previous day's kcal and protein, each with its status word.
struct NutritionPreviousDayCards: View {
    let row: NutritionDailyRow
    let isYesterday: Bool
    let kcalGoal: Double?
    let proteinGoal: Double?
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            JISectionHeader(isYesterday ? "Yesterday" : (nutritionDayParts(row.date)?.weekday ?? row.date))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { kcalCard; proteinCard }
                VStack(alignment: .leading, spacing: 12) { kcalCard; proteinCard }
            }
        }
        .accessibilityIdentifier("nutrition-previous-day")
    }

    private var kcalCard: some View {
        card(value: nutritionWholeText(row.kcalConsumed), unit: "kcal", role: nutritionKcalTintRole, missing: row.kcalConsumed == nil,
             status: macroKcalStatus(kcal: row.kcalConsumed, goal: kcalGoal, isToday: false), id: "kcal")
    }

    private var proteinCard: some View {
        card(value: nutritionWholeText(row.proteinG), unit: "g protein", role: .protein, missing: row.proteinG == nil,
             status: nutritionProteinStatus(protein: row.proteinG, goal: proteinGoal), id: "protein")
    }

    private func card(value: String, unit: String, role: JIColorRole, missing: Bool, status: String, id: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: value).jiNumeral(.numeralMedium).foregroundStyle(theme.color(missing ? .muted : role))
                    if !missing { Text(unit).jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true) }
                }
                Text(status).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit == "kcal" ? "Calories" : "Protein")
        .accessibilityValue("\(missing ? JIMissingReason.noData.rawValue : "\(value) \(unit)"), \(status)")
        .accessibilityIdentifier("nutrition-previous-\(id)")
    }
}

struct IdentifiedMeal: Identifiable { let detail: MealDetail; var id: String { detail.slot } }
