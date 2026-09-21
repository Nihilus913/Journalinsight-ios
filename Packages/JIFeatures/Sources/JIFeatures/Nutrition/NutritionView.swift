import SwiftUI
import JICore
import JIDesign

/// Nutrition tab (W3a-L2, frozen contract `NutritionView.init(model:)` — mirrors
/// `mobile/app/(tabs)/nutrition.tsx`): week strip → day select → meal timeline + macro card, plus
/// the +Log sheet. Rule 5 (never render a zero for missing data) and rule 6 (green reserved for
/// verdict/band/score/status) both apply throughout.
public struct NutritionView: View {
    @Bindable private var model: NutritionViewModel
    @State private var logSheetVisible = false
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: NutritionViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("nutrition-empty")
                case .loaded: loaded
                }
                logButton
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
        .sheet(isPresented: $logSheetVisible) {
            LogSheet(model: LogSheetViewModel(provider: model.provider)) {
                Task { await model.refresh() }
            }
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
            MealTimeline(day: model.day)
            WeeklyPlanNutritionRow(provider: model.provider) // W5b-L5: RN nutrition.tsx:292 "Weekly kcal / macro plan" row
        }
    }

    private var logButton: some View {
        Button { logSheetVisible = true } label: {
            Label("Log", systemImage: "plus").jiFont(.body, weight: .semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.color(.info))
        .accessibilityLabel("Add an entry")
        .accessibilityIdentifier("nutrition-log-button")
    }
}
