import SwiftUI
import JICore
import JIDesign

/// B-73: the editable form of `MacroGoals`. Every field starts empty ("Set your goal"): JI never
/// proposes a number. A typed kcal goal needs the REQUIRED basis choice before Save is enabled.
nonisolated struct NutritionDraft: Equatable, Sendable {
    var goalKcal: Double?
    /// nil = not chosen yet. true = "This already includes my deficit". false = "I want JI to subtract a deficit".
    var includesDeficit: Bool?
    /// The deficit field (only for `includesDeficit == false`). nil = empty.
    var deficitMode: KcalMode?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    init(_ g: MacroGoals) {
        goalKcal = g.kcal?.goalKcal
        switch g.kcal?.basis {
        case .includesDeficit: includesDeficit = true
        case .subtractDeficit(let mode): includesDeficit = false; deficitMode = mode
        case nil: includesDeficit = nil
        }
        proteinG = g.proteinG; carbsG = g.carbsG; fatG = g.fatG
        if case .weeklyLoss? = deficitMode { byWeek = true }
    }

    /// kcal/day ↔ kg/week toggle for the deficit field (7700 kcal/kg, input convenience only).
    /// Flipping it converts a typed deficit; an empty field stays empty.
    var byWeek = false {
        didSet {
            guard byWeek != oldValue, let perDay = deficitMode?.kcalPerDay else { return }
            deficitMode = byWeek
                ? .weeklyLoss(kgPerWeek: ((perDay * 7 / KcalMode.kcalPerKg) * 10).rounded() / 10)
                : .deficit(kcalPerDay: (perDay / 50).rounded() * 50)
        }
    }

    /// `.some(nil)` = no kcal goal typed (nothing to validate); `nil` = incomplete (choice or deficit missing).
    private var resolvedKcal: KcalGoal?? {
        guard let goalKcal else { return .some(nil) }            // no kcal goal typed: nothing to validate
        switch includesDeficit {
        case nil: return nil                                      // required choice missing
        case true?: return KcalGoal(goalKcal: goalKcal, basis: .includesDeficit)
        case false?:
            guard let deficitMode else { return nil }             // deficit field required
            return KcalGoal(goalKcal: goalKcal, basis: .subtractDeficit(deficitMode))
        }
    }

    /// The goals to save, or nil while the form is incomplete or the target would be ≤ 0.
    var goals: MacroGoals? {
        guard let kcal = resolvedKcal else { return nil }
        if let k = kcal, !k.isValid { return nil }
        return MacroGoals(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    var canSave: Bool { goals != nil }
}

/// W-B57-W2 fixer BUG-51: GoalsSetup's numbers are plain digits like Nutrition's ("1900", not the
/// locale's "1'900"), for the typed fields and the Plan band alike.
nonisolated let goalsSetupWholeNumberFormat = FloatingPointFormatStyle<Double>.number.grouping(.never)
nonisolated let goalsSetupDecimalFormat = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(1))

nonisolated func goalsSetupPlanBandText(_ band: (low: Int, high: Int)) -> String {
    "\(band.low)–\(band.high) kcal"
}

/// B-73: GoalsSetup's NUTRITION section. The board's "Calories 1617" stepper predates B-73 and is
/// replaced by the user's own daily kcal goal plus a required answer to "does it already include
/// my deficit?". The band (target ± 100) is read-only. Protein, carbs and fat are user-set and
/// start empty.
struct NutritionGoalsSection: View {
    @Environment(\.jiTheme) private var theme
    @Binding var draft: NutritionDraft
    let bandPreview: (low: Int, high: Int)?
    let impliedDeficit: String?
    let bandSettled: Bool

    private var deficitKcal: Binding<Double?> {
        Binding(get: { if case .deficit(let k)? = draft.deficitMode { k } else { nil } },
                set: { draft.deficitMode = $0.map { .deficit(kcalPerDay: $0) } })
    }
    private var weeklyKg: Binding<Double?> {
        Binding(get: { if case .weeklyLoss(let kg)? = draft.deficitMode { kg } else { nil } },
                set: { draft.deficitMode = $0.map { .weeklyLoss(kgPerWeek: $0) } })
    }

    var body: some View {
        Section {
            LabeledContent("Daily kcal goal") {
                TextField(MacroGoals.setGoalCopy, value: $draft.goalKcal, format: goalsSetupWholeNumberFormat)
                    .goalsNumericKeyboard(decimal: false).multilineTextAlignment(.trailing).monospacedDigit()
                    .accessibilityIdentifier("goals-setup-kcal-goal")
            }

            if draft.goalKcal != nil {
                basisRow("This already includes my deficit", selected: draft.includesDeficit == true, id: "goals-setup-basis-includes") {
                    draft.includesDeficit = true
                }
                basisRow("I want JI to subtract a deficit", selected: draft.includesDeficit == false, id: "goals-setup-basis-subtract") {
                    draft.includesDeficit = false
                }
                if draft.includesDeficit == nil {
                    Text("Choose one to save.").foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("goals-setup-basis-required")
                }
            }

            if draft.includesDeficit == false {
                Picker("Deficit by", selection: $draft.byWeek) {
                    Text("kcal a day").tag(false)
                    Text("kg a week").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("goals-setup-kcal-mode")

                if draft.byWeek {
                    LabeledContent("Weekly loss (kg)") {
                        TextField(MacroGoals.setGoalCopy, value: weeklyKg, format: goalsSetupDecimalFormat)
                            .goalsNumericKeyboard(decimal: true).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("goals-setup-weekly-loss")
                    }
                } else {
                    LabeledContent("Deficit (kcal a day)") {
                        TextField(MacroGoals.setGoalCopy, value: deficitKcal, format: goalsSetupWholeNumberFormat)
                            .goalsNumericKeyboard(decimal: false).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("goals-setup-deficit")
                    }
                }
            }

            LabeledContent("Plan band") {
                if let b = bandPreview {
                    Text(verbatim: goalsSetupPlanBandText(b)).monospacedDigit().foregroundStyle(theme.color(.text))
                } else {
                    Text(MacroGoals.setGoalCopy).foregroundStyle(theme.color(.muted))
                }
            }
            .accessibilityIdentifier("goals-setup-plan-band")

            if let impliedDeficit {
                Text(impliedDeficit).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("goals-setup-implied-deficit")
            }

            gramsRow("Protein", value: $draft.proteinG, id: "goals-setup-protein")
            gramsRow("Carbs", value: $draft.carbsG, id: "goals-setup-carbs")
            gramsRow("Fat", value: $draft.fatG, id: "goals-setup-fat")
        } header: {
            Text("Nutrition")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan band = your daily kcal target ± 100 kcal. The target is your goal, or your goal minus the deficit you set here.")
                Text(MacroGoals.trackerDisclaimer).accessibilityIdentifier("goals-setup-disclaimer")
                if !bandSettled {
                    Text(MacroGoals.bandSettleNote).accessibilityIdentifier("goals-setup-settle-note")
                }
                Text("Carbs sit in the meal after training, never before it.")
            }
            .foregroundStyle(theme.color(.muted))
        }
    }

    private func basisRow(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(theme.color(.text))
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(theme.color(.info)) }
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func gramsRow(_ title: String, value: Binding<Double?>, id: String) -> some View {
        LabeledContent("\(title) (g)") {
            TextField(MacroGoals.setGoalCopy, value: value, format: goalsSetupWholeNumberFormat)
                .goalsNumericKeyboard(decimal: false).multilineTextAlignment(.trailing).monospacedDigit()
                .accessibilityIdentifier(id)
        }
    }
}

// `.keyboardType` is iOS-only and fails to compile for the macOS host `swift test` builds
// against (same guard as `ConnectionSheet.swift`, controller ruling 2). No-op elsewhere.
private extension View {
    @ViewBuilder func goalsNumericKeyboard(decimal: Bool) -> some View {
        #if os(iOS)
        self.keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }
}
