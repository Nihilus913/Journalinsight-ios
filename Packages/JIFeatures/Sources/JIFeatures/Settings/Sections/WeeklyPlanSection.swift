import SwiftUI

// W5b-L5 (P-weekly-plan). Settings → Preferences row "Weekly kcal / macro plan" → pushes
// `WeeklyPlanView`. RN's real entry is the Nutrition tab's card (`nutrition.tsx:292`,
// `WeeklyPlanNutritionRow`); this row is the card's Settings entry, persisting through the same
// `PrefStore` (same on-disk file, same key) so both entries see one set of knobs.
public struct WeeklyPlanSection: SettingsSection {
    public static let sectionId = "l5.weeklyPlan"
    public let id = Self.sectionId
    public let title = "Weekly plan"
    public let systemImage = "calendar"
    public let sortKey = SettingsSortKey.preferences + 30
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { WeeklyPlanSectionRows() }
}

private struct WeeklyPlanSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Section {
            // B-57 W1 r5: the same goals provider the Nutrition-tab entry uses, so the plan's
            // "Matches your goal" reads the real goal instead of "No goal set".
            NavigationLink { WeeklyPlanView(model: model.makeWeeklyPlanModel()) } label: {
                SettingsLinkLabel(title: "Weekly kcal / macro plan", subtitle: "Bank rest-day calories for higher-carb training days — the deficit stays fixed")
            }
            .accessibilityLabel("Weekly kcal / macro plan")
            .accessibilityIdentifier("settings.row.weeklyPlan")
        }
    }
}
