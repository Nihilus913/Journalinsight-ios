import SwiftUI
import JICore
import JIDesign

/// W4-L3, mirrors `mobile/app/goals.tsx`: the local-only, ad-hoc freeform goal list. Local-only —
/// separate from `GoalsSetupView`'s structured, hub-backed targets (see that oracle's own header
/// comment / `GoalStore.ts`'s module comment for the two-feature split).
public struct GoalsView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: GoalsViewModel
    let now: () -> Date

    @State private var title = ""
    @State private var targetDate: String?

    public init(model: GoalsViewModel, now: @escaping () -> Date = Date.init) {
        self.model = model
        self.now = now
    }

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var todayString: String { String(now().ISO8601Format().prefix(10)) }

    public var body: some View {
        List {
            Section {
                TextField("Goal title", text: $title)
                    .accessibilityLabel("Goal title")
                    .accessibilityIdentifier("goals-new-title")
                GoalDatePicker(value: $targetDate)
                Button("Add goal") {
                    model.addGoal(title: title, targetDate: targetDate)
                    title = ""; targetDate = nil
                }
                .disabled(!canAdd)
                .accessibilityLabel("Add goal")
                .accessibilityIdentifier("goals-add")
            } header: {
                Text("New goal")
            }

            Section("Goals") {
                if model.isLoading {
                    Text("Loading…").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                } else if model.goals.isEmpty {
                    Text("No goals yet. Add one above to start tracking progress.")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                } else {
                    ForEach(model.goals) { goal in
                        GoalCard(
                            goal: goal,
                            today: todayString,
                            onStep: { delta in model.setProgress(id: goal.id, progress: goal.progress + delta) },
                            onDelete: { model.deleteGoal(id: goal.id) }
                        )
                    }
                }
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Goals")
        .task { model.load() }
    }
}
