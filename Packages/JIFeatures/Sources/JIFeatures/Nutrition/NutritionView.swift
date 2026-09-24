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
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: NutritionViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Spacer(); SyncedPill(date: model.fetchedAt, label: .lastSynced) }
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
        .navigationSubtitle(model.selectedDate)
        #endif
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
        .sheet(item: Binding(get: { selectedMeal.map(IdentifiedMeal.init) }, set: { selectedMeal = $0?.detail })) {
            MealDetailSheet(detail: $0.detail)
        }
    }

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
            JISectionHeader("Today")
            MacroSummaryCard(day: model.day)
            JISectionHeader("Meals")
            MealTimeline(day: model.day, onSelectMeal: { selectedMeal = $0 })
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

struct IdentifiedMeal: Identifiable { let detail: MealDetail; var id: String { detail.slot } }
