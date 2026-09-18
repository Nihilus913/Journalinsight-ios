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

    public init(model: NutritionViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(JIColor.muted) }
                        .accessibilityIdentifier("nutrition-empty")
                case .loaded: loaded
                }
                logButton
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
        .sheet(isPresented: $logSheetVisible) {
            LogSheet(model: LogSheetViewModel(provider: model.provider)) {
                Task { await model.refresh() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nutrition").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(model.selectedDate).font(.subheadline).foregroundStyle(JIColor.muted)
                .accessibilityLabel(model.selectedDate)
        }
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 60); SkeletonBlock(height: 120); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                    .accessibilityIdentifier("nutrition-error")
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
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
            MacroSummaryCard(day: model.day)
            MealTimeline(day: model.day)
        }
    }

    private var logButton: some View {
        Button { logSheetVisible = true } label: {
            Text("+ Log").font(.footnote.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(JIColor.info, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .foregroundStyle(JIColor.bg)
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("Add an entry")
        .accessibilityIdentifier("nutrition-log-button")
    }
}
