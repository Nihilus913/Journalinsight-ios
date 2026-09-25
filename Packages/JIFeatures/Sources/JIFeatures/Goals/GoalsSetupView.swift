import SwiftUI
import JICore
import JIDesign

/// B-57 W1: board order Weight, Nutrition, Strength (read-only next working weight), Activity.
/// W4-L3 (P-goals), mirrors `mobile/app/goals-setup.tsx`: the pinned structured-goals editor —
/// weight target/date, bench/row strength targets, daily steps, and the four nutrition macros.
/// Seeds its editable fields once from the loaded document (`hydrated`, same "not a live sync"
/// rule as the RN oracle's own `useRef` guard) so a background refresh never fights an in-progress
/// edit. CLAUDE.md rule 5: while loading (no seed yet) the form shows "Loading…", never zeros.
// W-FIX3 BUG-49: the target date is picked from a calendar and read as a date ("31 Oct 2026"),
// never typed or shown as the raw "2026-10-31" the hub stores. The wire format is unchanged.

/// Gregorian calendar-day helpers pinned to one time zone, so a picked day never shifts by one.
nonisolated private func goalsSetupCalendar(_ tz: TimeZone) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = tz
    return c
}

/// "2026-10-31" → that calendar day (noon, so no DST edge moves it); nil for blank or anything else.
public nonisolated func goalsSetupDate(_ iso: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
    let parts = iso.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    let cal = goalsSetupCalendar(timeZone)
    let comps = DateComponents(year: y, month: m, day: d, hour: 12)
    guard let date = cal.date(from: comps),
          cal.component(.month, from: date) == m, cal.component(.day, from: date) == d else { return nil }
    return date
}

/// The day back to the hub's "YYYY-MM-DD".
public nonisolated func goalsSetupISO(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
    let c = goalsSetupCalendar(timeZone).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// "2026-10-31" → "31 Oct 2026" (the VoiceOver value and the row when no picker is shown).
public nonisolated func goalsSetupDateLabel(_ iso: String) -> String {
    guard let date = goalsSetupDate(iso, timeZone: TimeZone(identifier: "UTC")!) else {
        return iso.trimmingCharacters(in: .whitespaces).isEmpty ? "No target date" : iso
    }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "d MMM yyyy"
    return f.string(from: date)
}

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

    private var dateValid: Bool {
        weightDate.trimmingCharacters(in: .whitespaces).isEmpty || goalsSetupDate(weightDate) != nil
    }

    private var canSave: Bool { dateValid && model.phase != .saving }

    /// On = a date is set (a fresh switch-on starts 12 weeks out); off = no target date.
    private var hasDateBinding: Binding<Bool> {
        Binding(
            get: { !weightDate.trimmingCharacters(in: .whitespaces).isEmpty },
            set: { on in
                weightDate = on ? goalsSetupISO(Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()) : ""
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { goalsSetupDate(weightDate) ?? Date() }, set: { weightDate = goalsSetupISO($0) })
    }

    public var body: some View {
        List {
            if !hydrated {
                Section { Text("Loading…").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
            } else {
                Section {
                    Stepper("Target weight: \(weightTarget, specifier: "%.1f") kg", value: $weightTarget, in: 30...400, step: 0.5)
                        .accessibilityIdentifier("goals-setup-weight-target")
                    Toggle(isOn: hasDateBinding) {
                        Text("Target date")
                    }
                    .tint(theme.color(.info))
                    .accessibilityIdentifier("goals-setup-weight-date-toggle")
                    if goalsSetupDate(weightDate) != nil {
                        DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                            .accessibilityLabel("Target date")
                            .accessibilityValue(goalsSetupDateLabel(weightDate))
                            .accessibilityIdentifier("goals-setup-weight-date")
                    }
                } header: {
                    Text("Weight")
                } footer: {
                    Text(dateValid ? "Target date is optional." : "That date could not be read — pick it again, or switch it off.")
                        .foregroundStyle(dateValid ? theme.color(.muted) : theme.color(.danger))
                }

                Section {
                    Stepper("Calories: \(Int(kcalGoal)) kcal", value: $kcalGoal, in: 1000...6000, step: 50)
                        .accessibilityIdentifier("goals-setup-kcal")
                    Stepper("Protein: \(Int(proteinG)) g", value: $proteinG, in: 0...400, step: 5)
                        .accessibilityIdentifier("goals-setup-protein")
                    Stepper("Carbs: \(Int(carbsG)) g", value: $carbsG, in: 0...600, step: 5)
                        .accessibilityIdentifier("goals-setup-carbs")
                    Stepper("Fat: \(Int(fatG)) g", value: $fatG, in: 0...300, step: 5)
                        .accessibilityIdentifier("goals-setup-fat")
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Carbs sit in the meal after training, never before it.")
                }

                // B-57 W1: read-only, from the local strength_state mirror. `benchTarget`/`rowTarget`
                // stay seeded and are sent unchanged by `save()`, so the hub document is not altered.
                Section {
                    ForEach(model.nextWorkingWeights, id: \.name) { w in
                        HStack {
                            Text(w.name).foregroundStyle(theme.color(.text))
                            Spacer()
                            Text(w.kg.map { "\(jiNumber($0, 1)) kg" } ?? "— \(JIMissingReason.noData.rawValue)")
                                .foregroundStyle(theme.color(w.kg == nil ? .muted : .sleep))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("goals-setup-next-\(w.name)")
                    }
                } header: {
                    Text("Strength · Next working weight")
                } footer: {
                    Text("Updates itself after each logged session. Nothing to type.")
                }

                Section("Activity") {
                    Stepper("Daily steps: \(stepsDaily)", value: $stepsDaily, in: 0...50000, step: 500)
                        .accessibilityIdentifier("goals-setup-steps-daily")
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
        .readableColumn()
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
