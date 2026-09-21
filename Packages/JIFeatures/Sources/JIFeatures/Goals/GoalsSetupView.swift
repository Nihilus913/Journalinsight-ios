import SwiftUI
import JICore
import JIDesign

/// W4-L3 (P-goals), mirrors `mobile/app/goals-setup.tsx`: the pinned structured-goals editor —
/// weight target/date, bench/row strength targets, daily steps, and the four nutrition macros.
/// Seeds its editable fields once from the loaded document (`hydrated`, same "not a live sync"
/// rule as the RN oracle's own `useRef` guard) so a background refresh never fights an in-progress
/// edit. CLAUDE.md rule 5: while loading (no seed yet) the form shows "Loading…", never zeros.
public struct GoalsSetupView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: GoalsSetupViewModel

    @State private var hydrated = false
    @State private var weightTarget: Double = 75
    @State private var weightDate: String = ""
    @State private var benchTarget: Double = 100
    @State private var rowTarget: Double = 100
    @State private var stepsDaily: Int = 15000
    @State private var kcalGoal: Double = 1800
    @State private var proteinG: Double = 172
    @State private var carbsG: Double = 160
    @State private var fatG: Double = 52

    public init(model: GoalsSetupViewModel) { self.model = model }

    private static let dateRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")

    private var dateValid: Bool {
        let trimmed = weightDate.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return Self.dateRE.firstMatch(in: trimmed, range: range) != nil
    }

    private var canSave: Bool { dateValid && model.phase != .saving }

    public var body: some View {
        List {
            if !hydrated {
                Section { Text("Loading…").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
            } else {
                Section {
                    Stepper("Target weight: \(weightTarget, specifier: "%.1f") kg", value: $weightTarget, in: 30...400, step: 0.5)
                        .accessibilityIdentifier("goals-setup-weight-target")
                    TextField("YYYY-MM-DD", text: $weightDate)
                        .accessibilityLabel("Target date (optional)")
                        .accessibilityIdentifier("goals-setup-weight-date")
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Weight")
                } footer: {
                    Text(dateValid ? "Target date is optional." : "Use YYYY-MM-DD, or leave blank.")
                        .foregroundStyle(dateValid ? theme.color(.muted) : theme.color(.danger))
                }

                Section("Strength") {
                    Stepper("Bench press: \(benchTarget, specifier: "%.1f") kg", value: $benchTarget, in: 0...500, step: 2.5)
                        .accessibilityIdentifier("goals-setup-bench-target")
                    Stepper("Bent-over row: \(rowTarget, specifier: "%.1f") kg", value: $rowTarget, in: 0...500, step: 2.5)
                        .accessibilityIdentifier("goals-setup-row-target")
                }

                Section("Activity") {
                    Stepper("Daily steps: \(stepsDaily)", value: $stepsDaily, in: 0...50000, step: 500)
                        .accessibilityIdentifier("goals-setup-steps-daily")
                }

                Section("Nutrition") {
                    Stepper("Calories: \(Int(kcalGoal)) kcal", value: $kcalGoal, in: 1000...6000, step: 50)
                        .accessibilityIdentifier("goals-setup-kcal")
                    Stepper("Protein: \(Int(proteinG)) g", value: $proteinG, in: 0...400, step: 5)
                        .accessibilityIdentifier("goals-setup-protein")
                    Stepper("Carbs: \(Int(carbsG)) g", value: $carbsG, in: 0...600, step: 5)
                        .accessibilityIdentifier("goals-setup-carbs")
                    Stepper("Fat: \(Int(fatG)) g", value: $fatG, in: 0...300, step: 5)
                        .accessibilityIdentifier("goals-setup-fat")
                }

                Section {
                    Button(action: save) {
                        Text(model.phase == .saving ? "Saving…" : "Save goals").frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save goals")
                    .accessibilityIdentifier("goals-setup-save")
                } footer: {
                    if case .error = model.phase {
                        Text("Couldn't save — try again.").foregroundStyle(theme.color(.danger))
                    } else if let savedAt = model.savedAt, model.phase == .loaded {
                        Text("Saved \(savedAt.formatted(date: .omitted, time: .shortened)).")
                    }
                }

                if let mirror = model.goals {
                    GoalTargetsMirrorSection(goals: mirror)
                }
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Goals setup")
        .task {
            await model.load()
            seedIfNeeded()
        }
        .onChange(of: model.goals) { _, _ in seedIfNeeded() }
    }

    private func seedIfNeeded() {
        guard !hydrated, let goals = model.goals else { return }
        hydrated = true
        weightTarget = goals.weight.targetKg
        weightDate = goals.weight.targetDate ?? ""
        benchTarget = goals.strength.first { $0.exercise == "bench" }?.targetKg ?? 100
        rowTarget = goals.strength.first { $0.exercise == "row" }?.targetKg ?? 100
        stepsDaily = goals.stepsDaily ?? 15000
        kcalGoal = goals.nutrition.kcalGoal ?? 1800
        proteinG = goals.nutrition.proteinG ?? 172
        carbsG = goals.nutrition.carbsG ?? 160
        fatG = goals.nutrition.fatG ?? 52
    }

    private func save() {
        guard canSave else { return }
        let trimmedDate = weightDate.trimmingCharacters(in: .whitespaces)
        let patch = GoalsUpdate(
            weight: .init(targetKg: weightTarget, targetDate: trimmedDate.isEmpty ? nil : trimmedDate),
            strength: [
                .init(exercise: "bench", targetKg: benchTarget),
                .init(exercise: "row", targetKg: rowTarget),
            ],
            stepsDaily: stepsDaily,
            nutrition: .init(kcalGoal: kcalGoal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        )
        Task { await model.save(patch) }
    }
}
