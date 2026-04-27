# SP5 — Domain Widgets + Detail Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 new widget types (Gate, Nutrition, Recovery, Energy, Strength) with compact home-screen cards and full-screen detail views, a shared Day Detail view, a simplified muscle map, and a Feel → JournalEntry bridge.

**Architecture:** Each widget type is a compact `View` struct that reads from a shared `HealthDataStore` (an `ObservableObject` that caches the latest health snapshot). Detail views are full-screen NavigationStack destinations. `DayDetailView` is a sheet triggered from any detail view's date row. `FeelEntrySheet` is presented after every auto-detected workout and creates a `JournalEntry`. No new SwiftData models. `HealthDataStore` caches Garmin daily rows and HealthKit snapshots from SP2/SP4.

**Tech Stack:** SwiftUI, SwiftData, HealthKit (via HealthKitReader from SP2), Garmin cache (from SP4 BGSync), Apple Testing framework.

**Prerequisites:** SP1 (WorkoutEntry), SP2 (HealthKitReader, RecoverySnapshot), SP3b (AssessmentEngine, AssessmentView), SP4 (ExerciseCatalogue, GarminDailySync cache).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Shared/HealthDataStore.swift` | Shared ObservableObject caching recovery + nutrition + strength snapshots |
| Create | `JournalInsight/Widgets/GateWidgetView.swift` | Compact gate recommendation chip |
| Create | `JournalInsight/Widgets/NutritionWidgetView.swift` | 7-day tracking dots + kcal/protein |
| Create | `JournalInsight/Widgets/RecoveryWidgetView.swift` | Sleep + body battery + RHR |
| Create | `JournalInsight/Widgets/EnergyWidgetView.swift` | Deficit + est. weekly Δweight |
| Create | `JournalInsight/Widgets/StrengthWidgetView.swift` | Muscle balance summary |
| Create | `JournalInsight/DomainDetail/NutritionDetailView.swift` | Full macro log + TQ history |
| Create | `JournalInsight/DomainDetail/RecoveryDetailView.swift` | Sleep stages + HRV + ACWR daily log |
| Create | `JournalInsight/DomainDetail/EnergyDetailView.swift` | TDEE + deficit table |
| Create | `JournalInsight/DomainDetail/StrengthDetailView.swift` | 4-tab: Muscle Focus, Muscle Map, Session Log, Progression |
| Create | `JournalInsight/DomainDetail/MuscleMapView.swift` | SwiftUI capsule grid (no third-party lib) |
| Create | `JournalInsight/DomainDetail/DayDetailView.swift` | Per-day meals + activities + sets sheet |
| Create | `JournalInsight/Training/FeelEntrySheet.swift` | Post-workout feel → creates JournalEntry |
| Modify | `JournalInsight/MainScreenView.swift` | Add 5 new WidgetType cases + routing |
| Modify | `JournalInsight/JournalInsightApp.swift` | Inject HealthDataStore as environment object |
| Modify | `JournalInsight/HealthKit/HealthKitObserver.swift` | Trigger FeelEntrySheet after auto-detected workout |

---

## Task 1: HealthDataStore

**Files:**
- Create: `JournalInsight/Shared/HealthDataStore.swift`

- [ ] **Step 1.1: Create the file**

```swift
// JournalInsight/Shared/HealthDataStore.swift
import SwiftUI
import Foundation

// Shared cache of the latest health data snapshot.
// Populated by BackgroundSyncManager and manual sync.
// Views observe this — no direct HealthKit calls from widgets.
@MainActor
final class HealthDataStore: ObservableObject {

    // MARK: — Published state

    @Published var recovery: RecoverySnapshot = RecoverySnapshot()
    @Published var garminRows: [[String: Double?]] = []   // from SP4 BGSync cache
    @Published var nutritionRows: [[String: Double?]] = [] // from HealthKit nutrition
    @Published var workoutEntries: [WorkoutEntry] = []    // set externally from SwiftData
    @Published var assessment: TrainingAssessment? = nil
    @Published var isLoading: Bool = false
    @Published var lastRefreshed: Date? = nil

    // MARK: — Derived (computed from cached rows)

    var derivedMetrics: DerivedMetrics {
        let allRows = garminRows.isEmpty ? nutritionRows : garminRows
        return DerivedMetrics(from: allRows)
    }

    var trackingDots: [TrackingDay] {
        let cal = Calendar.current
        return (0..<7).reversed().map { daysAgo -> TrackingDay in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
            let dateStr = DateFormatter.yyyyMMdd.string(from: date)
            // Find matching row in garmin/nutrition rows by date string
            let row = (garminRows + nutritionRows).first {
                ($0["date"] as? String ?? "") == dateStr
            }
            let kcal = row?["kcal_consumed"] as? Double ?? nil
            let meals = row?["meals_logged"] as? Double ?? nil
            return TrackingDay(date: date, kcal: kcal, meals: meals.map { Int($0) })
        }
    }

    // MARK: — Refresh

    func refresh(reader: HealthKitReader) async {
        isLoading = true
        defer { isLoading = false; lastRefreshed = .now }

        // Load Garmin rows from BGSync cache
        if let data = UserDefaults.standard.data(forKey: "garminDailyRowsCache"),
           let rows = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            garminRows = rows.map { $0.mapValues { Optional($0) } }
        }

        // Load HealthKit recovery
        recovery = await reader.latestRecovery()
    }
}

struct TrackingDay: Identifiable {
    let id = UUID()
    let date: Date
    let kcal: Double?
    let meals: Int?

    var quality: TrackingQuality {
        guard let m = meals else { return .noData }
        guard let k = kcal else { return m >= 1 ? .partial : .noData }
        if m >= 3 && k >= 1200 { return .full }
        if m >= 1 { return .partial }
        return .notTracked
    }
}

enum TrackingQuality {
    case full       // ≥3 meals + ≥1200 kcal
    case partial    // ≥1 meal
    case notTracked // 0 meals logged
    case noData     // no sync data

    var color: Color {
        switch self {
        case .full:       return .green
        case .partial:    return .yellow
        case .notTracked: return .red
        case .noData:     return Color.gray.opacity(0.4)
        }
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
```

- [ ] **Step 1.2: Inject HealthDataStore in JournalInsightApp.swift**

```swift
// Add as @StateObject in JournalInsightApp
@StateObject private var healthData = HealthDataStore()
```

Pass to the window group:
```swift
MainScreenView()
    .environmentObject(healthData)
    // ... existing modifiers
```

- [ ] **Step 1.3: Build — expect no errors**

- [ ] **Step 1.4: Commit**

```bash
git add JournalInsight/Shared/HealthDataStore.swift JournalInsight/JournalInsightApp.swift
git commit -m "feat(sp5): add HealthDataStore shared health data cache"
```

---

## Task 2: Add 5 new WidgetType cases to MainScreenView

**Files:**
- Modify: `JournalInsight/MainScreenView.swift`

- [ ] **Step 2.1: Add cases to WidgetType enum**

```swift
enum WidgetType: String, Codable, CaseIterable {
    case streak, session, questions, calendar, goals,
         training, gate, nutrition, recovery, energy, strength

    var title: String {
        switch self {
        case .gate:      return "Gate"
        case .nutrition: return "Nutrition"
        case .recovery:  return "Recovery"
        case .energy:    return "Energy"
        case .strength:  return "Strength"
        // ... existing cases unchanged ...
        default: fatalError("add title for \(self)")
        }
    }

    var systemImage: String {
        switch self {
        case .gate:      return "arrow.up.arrow.down.circle.fill"
        case .nutrition: return "fork.knife.circle.fill"
        case .recovery:  return "moon.zzz.fill"
        case .energy:    return "bolt.fill"
        case .strength:  return "dumbbell.fill"
        // ... existing cases unchanged ...
        default: fatalError("add icon for \(self)")
        }
    }
}
```

- [ ] **Step 2.2: Add stubs to WidgetCardView switch**

```swift
case .gate:      GateWidgetView()
case .nutrition: NutritionWidgetView()
case .recovery:  RecoveryWidgetView()
case .energy:    EnergyWidgetView()
case .strength:  StrengthWidgetView()
```

These views are created in Tasks 3–7. Add stubs now so the project builds:

```swift
// Temporary stubs in MainScreenView.swift (will be replaced by individual files)
struct GateWidgetView: View      { var body: some View { Text("Gate") } }
struct NutritionWidgetView: View { var body: some View { Text("Nutrition") } }
struct RecoveryWidgetView: View  { var body: some View { Text("Recovery") } }
struct EnergyWidgetView: View    { var body: some View { Text("Energy") } }
struct StrengthWidgetView: View  { var body: some View { Text("Strength") } }
```

- [ ] **Step 2.3: Add routing in destinationView(for:)**

```swift
case .gate:      NutritionDetailView()   // gate panel is top of Nutrition detail
case .nutrition: NutritionDetailView()
case .recovery:  RecoveryDetailView()
case .energy:    EnergyDetailView()
case .strength:  StrengthDetailView()
```

Add stub detail view files to compile:

```swift
struct NutritionDetailView: View { var body: some View { Text("Nutrition Detail") } }
struct RecoveryDetailView: View  { var body: some View { Text("Recovery Detail") } }
struct EnergyDetailView: View    { var body: some View { Text("Energy Detail") } }
struct StrengthDetailView: View  { var body: some View { Text("Strength Detail") } }
```

- [ ] **Step 2.4: Build — expect no errors**

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/MainScreenView.swift
git commit -m "feat(sp5): add gate/nutrition/recovery/energy/strength WidgetType cases + stubs"
```

---

## Task 3: Compact widget views

**Files:**
- Create: `JournalInsight/Widgets/GateWidgetView.swift`
- Create: `JournalInsight/Widgets/NutritionWidgetView.swift`
- Create: `JournalInsight/Widgets/RecoveryWidgetView.swift`
- Create: `JournalInsight/Widgets/EnergyWidgetView.swift`
- Create: `JournalInsight/Widgets/StrengthWidgetView.swift`

- [ ] **Step 3.1: Create GateWidgetView.swift**

```swift
// JournalInsight/Widgets/GateWidgetView.swift
import SwiftUI

struct GateWidgetView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var rec: Recommendation? { store.assessment?.recommendation }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(rec?.color ?? .gray)
                Text("Gate").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            if let r = rec {
                Text(r.label)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(r.color)
                Text(r.shortRationale)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Loading…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension Recommendation {
    var shortRationale: String {
        switch self {
        case .progress: return "Fuelling on target · load has headroom"
        case .maintain: return "Stable signals · proceed as planned"
        case .reduce:   return "High load or low fuelling"
        case .rest:     return "Active recovery recommended"
        }
    }
}
```

- [ ] **Step 3.2: Create NutritionWidgetView.swift**

```swift
// JournalInsight/Widgets/NutritionWidgetView.swift
import SwiftUI

struct NutritionWidgetView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var m: DerivedMetrics { store.derivedMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "fork.knife.circle.fill").foregroundStyle(.green)
                Text("Nutrition").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            // 7-day tracking dots
            HStack(spacing: 4) {
                ForEach(store.trackingDots) { day in
                    Circle()
                        .fill(day.quality.color)
                        .frame(width: 10, height: 10)
                }
            }
            // Today's kcal + protein
            HStack(spacing: 12) {
                if let kcal = m.avgKcal {
                    Label(String(format: "%.0f kcal", kcal), systemImage: "flame")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let p = m.avgProtein {
                    Label(String(format: "%.0f g protein", p), systemImage: "bolt.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 3.3: Create RecoveryWidgetView.swift**

```swift
// JournalInsight/Widgets/RecoveryWidgetView.swift
import SwiftUI

struct RecoveryWidgetView: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
                Text("Recovery").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                if let dur = store.recovery.sleepDurationSec {
                    Label(String(format: "%.1fh", dur / 3600), systemImage: "moon.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let rhr = store.recovery.restingHR {
                    Label("\(Int(rhr)) bpm", systemImage: "heart")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let hrv = store.recovery.hrv {
                    Label("\(Int(hrv))ms", systemImage: "waveform.path.ecg")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 3.4: Create EnergyWidgetView.swift**

```swift
// JournalInsight/Widgets/EnergyWidgetView.swift
import SwiftUI

struct EnergyWidgetView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var m: DerivedMetrics { store.derivedMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("Energy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            if let def = m.avgKcalDeficit {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", abs(def)))
                        .font(.title2.weight(.bold))
                    Text("kcal \(def > 0 ? "deficit" : "surplus")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let Δw = m.estWeeklyWeightChangeKg {
                Text(String(format: "Est. %.2f kg/week", abs(Δw)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3.5: Create StrengthWidgetView.swift**

```swift
// JournalInsight/Widgets/StrengthWidgetView.swift
import SwiftUI
import SwiftData

struct StrengthWidgetView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]

    private var allSets: [LoggedExercise] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now)!
        return entries.filter { $0.date >= cutoff }.flatMap { $0.exercises }
    }

    private var muscleBalance: (balanced: Int, moderate: Int, undertrained: Int) {
        let categories = Set(allSets.map { $0.garminExerciseName ?? $0.name })
        var bal = 0, mod = 0, under = 0
        for group in MuscleGroup.allCases where group != .cardio {
            let trained = ExerciseCatalogue.entries
                .filter { $0.muscleGroups.contains(group) }
                .contains { e in categories.contains { $0.lowercased().contains(e.garminCategory.lowercased()) } }
            if trained { bal += 1 } else { under += 1 }
        }
        return (bal, mod, under)
    }

    private var daysSince: Int? {
        guard let last = entries.first else { return nil }
        return Calendar.current.dateComponents([.day], from: last.date, to: .now).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
                Text("Strength").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            let b = muscleBalance
            HStack(spacing: 8) {
                statCapsule("\(b.balanced)", color: .green, icon: "checkmark")
                statCapsule("\(b.moderate)", color: .yellow, icon: "minus")
                statCapsule("\(b.undertrained)", color: .red, icon: "exclamationmark")
            }
            if let d = daysSince {
                Text(d == 0 ? "Trained today" : "\(d)d since last session")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func statCapsule(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
    }
}
```

- [ ] **Step 3.6: Remove stubs from MainScreenView.swift**

Delete the 5 stub structs added in Task 2 from `MainScreenView.swift`.

- [ ] **Step 3.7: Build and run — all 5 new widgets should appear in the widget picker**

- [ ] **Step 3.8: Commit**

```bash
git add JournalInsight/Widgets/ JournalInsight/MainScreenView.swift
git commit -m "feat(sp5): add compact widget views for gate/nutrition/recovery/energy/strength"
```

---

## Task 4: DayDetailView (shared sheet)

**Files:**
- Create: `JournalInsight/DomainDetail/DayDetailView.swift`

- [ ] **Step 4.1: Create the file**

```swift
// JournalInsight/DomainDetail/DayDetailView.swift
import SwiftUI
import SwiftData

struct DayDetailView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var allWorkouts: [WorkoutEntry]

    private var workoutsOnDate: [WorkoutEntry] {
        let cal = Calendar.current
        return allWorkouts.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    private var exercises: [LoggedExercise] { workoutsOnDate.flatMap { $0.exercises } }

    var body: some View {
        NavigationStack {
            List {
                // Activities section
                if !workoutsOnDate.isEmpty {
                    Section("Workouts") {
                        ForEach(workoutsOnDate) { w in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(w.source.rawValue.capitalized)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(w.durationSec / 60) min")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let notes = w.notes {
                                    Text(notes).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Strength sets section
                if !exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { _, ex in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).font(.subheadline.weight(.medium))
                                    Text("\(ex.sets) sets × \(ex.reps) reps")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let kg = ex.weightKg, kg > 0 {
                                    Text(String(format: "%.1f kg", kg))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }

                if workoutsOnDate.isEmpty {
                    Section {
                        Text("No workout data for this day.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Meal and nutrition data pulled from YAZIO via HealthKit.")
                        .font(.caption).foregroundStyle(.secondary).italic()
                }
            }
            .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 4.2: Build — expect no errors**

- [ ] **Step 4.3: Commit**

```bash
git add JournalInsight/DomainDetail/DayDetailView.swift
git commit -m "feat(sp5): add DayDetailView — workouts + exercise sets per day"
```

---

## Task 5: NutritionDetailView + EnergyDetailView + RecoveryDetailView

**Files:**
- Create: `JournalInsight/DomainDetail/NutritionDetailView.swift`
- Create: `JournalInsight/DomainDetail/EnergyDetailView.swift`
- Create: `JournalInsight/DomainDetail/RecoveryDetailView.swift`

- [ ] **Step 5.1: Create NutritionDetailView.swift**

```swift
// JournalInsight/DomainDetail/NutritionDetailView.swift
import SwiftUI

struct NutritionDetailView: View {
    @EnvironmentObject private var store: HealthDataStore
    @State private var selectedDate: Date? = nil

    private var m: DerivedMetrics { store.derivedMetrics }

    var body: some View {
        List {
            // Gate assessment at top
            if let a = store.assessment {
                Section { AssessmentView(assessment: a) }
            }

            // 7-day tracking dots
            Section("Tracking Quality (7 days)") {
                HStack(spacing: 8) {
                    ForEach(store.trackingDots) { day in
                        VStack(spacing: 4) {
                            Circle().fill(day.quality.color).frame(width: 14, height: 14)
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .onTapGesture { selectedDate = day.date }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Averages
            Section("7-day Averages") {
                row("Kcal consumed",  value: m.avgKcal,    unit: "kcal")
                row("Protein",        value: m.avgProtein, unit: "g")
                row("Goal ratio",     value: m.avgKcalGoalRatio.map { $0 * 100 }, unit: "%")
                row("Protein / kg",   value: m.proteinPerKg, unit: "g/kg")
            }
        }
        .navigationTitle("Nutrition")
        .sheet(item: Binding(
            get: { selectedDate.map { IdentifiableDate(date: $0) } },
            set: { selectedDate = $0?.date }
        )) { id in
            DayDetailView(date: id.date)
        }
    }

    private func row(_ label: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { String(format: "%.0f \(unit)", $0) } ?? "—")
                .font(.subheadline.weight(.medium))
        }
    }
}

struct IdentifiableDate: Identifiable { let id = UUID(); let date: Date }
```

- [ ] **Step 5.2: Create EnergyDetailView.swift**

```swift
// JournalInsight/DomainDetail/EnergyDetailView.swift
import SwiftUI

struct EnergyDetailView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var m: DerivedMetrics { store.derivedMetrics }

    var body: some View {
        List {
            Section("Energy Balance (7-day avg)") {
                row("Avg intake",      value: m.avgKcal, unit: "kcal/day")
                row("TDEE (Garmin)",   value: store.garminRows.isEmpty ? nil : m.avgKcalBurned, unit: "kcal/day")
                row("Avg deficit",     value: m.avgKcalDeficit, unit: "kcal/day", positive: "deficit", negative: "surplus")
                row("Est Δweight",     value: m.estWeeklyWeightChangeKg, unit: "kg/week")
            }

            // Compliance warning
            let trackingDays = store.trackingDots.filter { $0.quality == .full }.count
            if trackingDays < DerivedMetrics.minTrackedDays {
                Section {
                    Label(
                        "Only \(trackingDays)/7 days fully tracked — averages may not be reliable.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.yellow)
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Energy")
    }

    private func row(_ label: String, value: Double?, unit: String,
                     positive: String = "", negative: String = "") -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let v = value {
                let display = positive.isEmpty
                    ? String(format: "%.0f \(unit)", v)
                    : (v > 0 ? String(format: "%.0f \(unit) \(positive)", v)
                              : String(format: "%.0f \(unit) \(negative)", abs(v)))
                Text(display).font(.subheadline.weight(.medium))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 5.3: Create RecoveryDetailView.swift**

```swift
// JournalInsight/DomainDetail/RecoveryDetailView.swift
import SwiftUI

struct RecoveryDetailView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var r: RecoverySnapshot { store.recovery }

    var body: some View {
        List {
            Section("Last Night") {
                if let dur = r.sleepDurationSec {
                    row("Sleep duration", value: String(format: "%.1fh", dur / 3600))
                }
                if let deep = r.deepSleepSec, let dur = r.sleepDurationSec, dur > 0 {
                    row("Deep sleep", value: String(format: "%.0f%%", deep / dur * 100))
                }
            }

            Section("Biometrics") {
                if let rhr = r.restingHR { row("Resting HR", value: "\(Int(rhr)) bpm") }
                if let hrv = r.hrv       { row("HRV",        value: "\(Int(hrv)) ms") }
            }

            Section("Training Load") {
                if let acwr = store.derivedMetrics.acwr {
                    row("ACWR", value: String(format: "%.2f", acwr))
                } else {
                    row("ACWR", value: "—")
                }
            }

            if let updated = r.lastUpdated {
                Section {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Recovery")
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }
}
```

- [ ] **Step 5.4: Remove stubs from MainScreenView.swift** (the three stubs added in Task 2 for these views)

- [ ] **Step 5.5: Build — expect no errors**

- [ ] **Step 5.6: Commit**

```bash
git add JournalInsight/DomainDetail/NutritionDetailView.swift \
        JournalInsight/DomainDetail/EnergyDetailView.swift \
        JournalInsight/DomainDetail/RecoveryDetailView.swift \
        JournalInsight/MainScreenView.swift
git commit -m "feat(sp5): add NutritionDetailView, EnergyDetailView, RecoveryDetailView"
```

---

## Task 6: MuscleMapView + StrengthDetailView

**Files:**
- Create: `JournalInsight/DomainDetail/MuscleMapView.swift`
- Create: `JournalInsight/DomainDetail/StrengthDetailView.swift`

- [ ] **Step 6.1: Create MuscleMapView.swift**

```swift
// JournalInsight/DomainDetail/MuscleMapView.swift
import SwiftUI

// Simplified SwiftUI capsule grid — front/back muscle groups.
// No third-party SVG library required.
struct MuscleMapView: View {
    let trainedCategories: Set<String>  // Garmin category strings (e.g. "BENCH_PRESS", "ROW")
    let cardioActive: Bool              // true if cardio sessions in last 28 days

    private let frontMuscles: [(muscle: MuscleGroup, label: String)] = [
        (.chest, "Chest"), (.shoulders, "Shoulders"), (.biceps, "Biceps"),
        (.triceps, "Triceps"), (.core, "Core"), (.legs, "Quads"),
    ]

    private let backMuscles: [(muscle: MuscleGroup, label: String)] = [
        (.back, "Back"), (.back, "Traps"), (.glutes, "Glutes"),
        (.legs, "Hamstrings"), (.legs, "Calves"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            muscleColumn("FRONT", muscles: frontMuscles)
            muscleColumn("BACK", muscles: backMuscles)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func muscleColumn(_ title: String, muscles: [(muscle: MuscleGroup, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(muscles, id: \.label) { item in
                let status = muscleStatus(item.muscle)
                HStack(spacing: 6) {
                    Circle().fill(status.color).frame(width: 10, height: 10)
                    Text(item.label).font(.caption)
                }
            }
        }
    }

    private func muscleStatus(_ group: MuscleGroup) -> MuscleStatus {
        let groupCategories = ExerciseCatalogue.entries
            .filter { $0.muscleGroups.contains(group) }
            .map { $0.garminCategory }
        let trained = groupCategories.contains { trainedCategories.contains($0) }
        if !trained && (group == .legs || group == .glutes) && cardioActive { return .cardio }
        if trained { return .balanced }
        return .untrained
    }
}

enum MuscleStatus {
    case balanced, moderate, undertrained, untrained, cardio

    var color: Color {
        switch self {
        case .balanced:    return .green
        case .moderate:    return .yellow
        case .undertrained: return .red
        case .untrained:   return Color.gray.opacity(0.3)
        case .cardio:      return .blue
        }
    }
}
```

- [ ] **Step 6.2: Create StrengthDetailView.swift**

```swift
// JournalInsight/DomainDetail/StrengthDetailView.swift
import SwiftUI
import SwiftData

enum StrengthTab: String, CaseIterable {
    case focus = "Muscle Focus"
    case map   = "Muscle Map"
    case log   = "Session Log"
    case progression = "Progression"
}

struct StrengthDetailView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]
    @State private var tab: StrengthTab = .focus
    @State private var selectedDate: Date? = nil

    private var recentEntries: [WorkoutEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now)!
        return entries.filter { $0.date >= cutoff }
    }

    private var allExercises: [LoggedExercise] { recentEntries.flatMap { $0.exercises } }

    private var trainedCategories: Set<String> {
        Set(allExercises.compactMap { ex in
            ExerciseCatalogue.resolve(ex.name)?.garminCategory
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("View", selection: $tab) {
                ForEach(StrengthTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .focus:       muscleFocusTab
            case .map:         muscleMapTab
            case .log:         sessionLogTab
            case .progression: progressionTab
            }
        }
        .navigationTitle("Strength")
        .sheet(item: Binding(
            get: { selectedDate.map { IdentifiableDate(date: $0) } },
            set: { selectedDate = $0?.date }
        )) { id in
            DayDetailView(date: id.date)
        }
    }

    // MARK: — Muscle Focus tab

    private var muscleFocusTab: some View {
        List {
            ForEach(MuscleGroup.allCases.filter { $0 != .cardio }, id: \.self) { group in
                let cats = ExerciseCatalogue.entries.filter { $0.muscleGroups.contains(group) }.map { $0.garminCategory }
                let trained = cats.contains { trainedCategories.contains($0) }
                HStack {
                    Circle()
                        .fill(trained ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(group.rawValue.capitalized)
                    Spacer()
                    Text(trained ? "Trained" : "Not trained")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: — Muscle Map tab

    private var muscleMapTab: some View {
        ScrollView {
            MuscleMapView(trainedCategories: trainedCategories, cardioActive: false)
                .padding()
        }
    }

    // MARK: — Session Log tab

    private var sessionLogTab: some View {
        List {
            ForEach(recentEntries) { entry in
                Section(entry.date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(Array(entry.exercises.enumerated()), id: \.offset) { _, ex in
                        HStack {
                            Text(ex.name)
                            Spacer()
                            Text("\(ex.sets)×\(ex.reps)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let kg = ex.weightKg, kg > 0 {
                                Text(String(format: "%.1fkg", kg))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .onTapGesture { selectedDate = entry.date }
                }
            }
        }
    }

    // MARK: — Progression tab

    private var progressionTab: some View {
        List {
            Text("Progression editing is available in Settings → Training Plan.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(groupedByName, id: \.0) { name, exerciseList in
                Section(name) {
                    if let latest = exerciseList.first {
                        HStack {
                            Text("Latest weight")
                            Spacer()
                            if let kg = latest.weightKg, kg > 0 {
                                Text(String(format: "%.1f kg", kg)).font(.subheadline.weight(.semibold))
                            } else {
                                Text("Bodyweight").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("\(exerciseList.count) sets logged (28 days)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var groupedByName: [(String, [LoggedExercise])] {
        var dict: [String: [LoggedExercise]] = [:]
        for ex in allExercises { dict[ex.name, default: []].append(ex) }
        return dict.sorted { $0.key < $1.key }
    }
}
```

- [ ] **Step 6.3: Remove the StrengthDetailView stub from MainScreenView.swift**

- [ ] **Step 6.4: Build and run — navigate to Strength widget → all 4 tabs should render**

- [ ] **Step 6.5: Commit**

```bash
git add JournalInsight/DomainDetail/MuscleMapView.swift \
        JournalInsight/DomainDetail/StrengthDetailView.swift \
        JournalInsight/MainScreenView.swift
git commit -m "feat(sp5): add StrengthDetailView with 4 tabs + MuscleMapView capsule grid"
```

---

## Task 7: FeelEntrySheet — Feel → JournalEntry bridge

**Files:**
- Create: `JournalInsight/Training/FeelEntrySheet.swift`
- Modify: `JournalInsight/HealthKit/HealthKitObserver.swift`

- [ ] **Step 7.1: Create FeelEntrySheet.swift**

```swift
// JournalInsight/Training/FeelEntrySheet.swift
import SwiftUI
import SwiftData

struct FeelEntrySheet: View {
    let workout: WorkoutEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var feelScore: Int? = nil
    @State private var notes: String = ""
    @State private var saved = false

    // Pre-filled workout summary
    private var workoutSummary: String {
        let dur = "\(workout.durationSec / 60) min"
        let exSummary = workout.exercises.prefix(3).map { ex in
            let w = ex.weightKg.map { String(format: " @ %.1fkg", $0) } ?? ""
            return "\(ex.name) \(ex.sets)×\(ex.reps)\(w)"
        }.joined(separator: "\n")
        return exSummary.isEmpty ? "Workout: \(dur)" : "Workout (\(dur)):\n\(exSummary)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("How did the session feel?") {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { score in
                            Button {
                                feelScore = score
                            } label: {
                                VStack(spacing: 4) {
                                    Text(moodEmoji(for: score))
                                        .font(.title)
                                    Text("\(score)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(feelScore == score ? Color.blue.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Section("Session summary") {
                    Text(workoutSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Log Session Feel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(feelScore == nil || saved)
                }
            }
            .overlay {
                if saved {
                    Text("Saved!")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: — Private

    private func save() {
        guard let score = feelScore else { return }
        let mood = Mood.from(feelScore: score)
        let body = workoutSummary + (notes.isEmpty ? "" : "\n\n\(notes)")
        let entry = JournalEntry(
            date: workout.date,
            text: body,
            duration: TimeInterval(workout.durationSec),
            mood: mood
        )
        // Auto-apply "workout" tag if it exists, create if not
        let tagDescriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == "workout" })
        if let existing = try? modelContext.fetch(tagDescriptor).first {
            entry.tags = [existing]
        } else {
            let tag = Tag(name: "workout")
            modelContext.insert(tag)
            entry.tags = [tag]
        }
        modelContext.insert(entry)
        try? modelContext.save()
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 5: return "😄"
        case 4: return "🙂"
        case 3: return "😐"
        case 2: return "😕"
        default: return "😣"
        }
    }
}

private extension Mood {
    // Maps feel score 1–5 to Mood enum
    static func from(feelScore: Int) -> Mood {
        switch feelScore {
        case 5: return .great
        case 4: return .good
        case 3: return .okay
        case 2: return .bad
        default: return .terrible
        }
    }
}
```

- [ ] **Step 7.2: Trigger FeelEntrySheet from TrainingDetailView**

In `TrainingDetailView`, add:

```swift
@State private var workoutForFeel: WorkoutEntry? = nil
```

After inserting a `WorkoutEntry` (in `ManualWorkoutLogSheet.save()`, trigger via environment or notification — simplest approach: add a `.sheet` in `TrainingDetailView` driven by the latest entry):

In `TrainingDetailView.body`, add the sheet:

```swift
.sheet(item: $workoutForFeel) { w in
    FeelEntrySheet(workout: w)
}
```

Add an `.onChange` on entries to trigger the sheet for new entries:

```swift
.onChange(of: entries.first?.date) { _, newDate in
    // A new entry appeared — prompt for feel if source is healthKit or garmin
    if let newest = entries.first, newest.source != .manual {
        workoutForFeel = newest
    }
}
```

- [ ] **Step 7.3: Build and run — complete a workout in Fitness app, open JournalInsight → FeelEntrySheet should appear**

(Testing on device with HealthKit is required for this flow.)

- [ ] **Step 7.4: Commit**

```bash
git add JournalInsight/Training/FeelEntrySheet.swift \
        JournalInsight/Training/TrainingDetailView.swift
git commit -m "feat(sp5): add FeelEntrySheet — post-workout feel score creates JournalEntry"
```

---

## SP5 complete

Run full test suite (`⌘U`). All existing tests must pass.

```bash
git log --oneline -12
```

Expected commits:
```
feat(sp5): add FeelEntrySheet — post-workout feel score creates JournalEntry
feat(sp5): add StrengthDetailView with 4 tabs + MuscleMapView capsule grid
feat(sp5): add NutritionDetailView, EnergyDetailView, RecoveryDetailView
feat(sp5): add DayDetailView — workouts + exercise sets per day
feat(sp5): add compact widget views for gate/nutrition/recovery/energy/strength
feat(sp5): add gate/nutrition/recovery/energy/strength WidgetType cases + stubs
feat(sp5): add HealthDataStore shared health data cache
```
