# SP1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WorkoutEntry model, training streak, Training widget, manual workout log, and workout-day notifications to JournalInsight.

**Architecture:** SwiftData `WorkoutEntry` model mirrors `JournalEntry` structure. `TrainingStreakCalculator` is a parallel enum to `StreakCalculator`. A new `.training` `WidgetType` case drives a `TrainingWidgetView` (compact card) and `TrainingDetailView` (full screen). `NotificationManager` gains workout-specific scheduling. All state stays in views as `@State`/`@Query` — no new ViewModels.

**Tech Stack:** SwiftUI, SwiftData, UserNotifications, Apple Testing framework (`@Suite`/`@Test`/`#expect`), Xcode 16+, iOS 18.4.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/WorkoutEntry.swift` | WorkoutEntry `@Model`, WorkoutSource enum, LoggedExercise struct |
| Create | `JournalInsight/Training/TrainingStreakCalculator.swift` | Streak logic over `[WorkoutEntry]` |
| Create | `JournalInsight/Training/TrainingWidgetView.swift` | Compact `.training` widget card content |
| Create | `JournalInsight/Training/TrainingDetailView.swift` | Full-screen training screen (streak, milestones, manual log button) |
| Create | `JournalInsight/Training/ManualWorkoutLogSheet.swift` | Sheet: date + duration + notes → creates WorkoutEntry |
| Modify | `JournalInsight/JournalInsightApp.swift` | Add WorkoutEntry to ModelContainer |
| Modify | `JournalInsight/MainScreenView.swift` | Add `.training` WidgetType case, routing, widget card |
| Modify | `JournalInsight/NotificationManager.swift` | Add `scheduleWorkoutReminder(weekdays:hour:minute:planSummary:)` + `cancelWorkoutReminder()` |
| Modify | `JournalInsight/SettingsView.swift` | Add Training section (workout days, reminder time, Garmin placeholder) |
| Create | `JournalInsightTests/TrainingStreakCalculatorTests.swift` | Tests for TrainingStreakCalculator |
| Create | `JournalInsightTests/WorkoutEntryTests.swift` | Tests for WorkoutEntry model |

---

## Task 1: WorkoutEntry model

**Files:**
- Create: `JournalInsight/WorkoutEntry.swift`
- Create: `JournalInsightTests/WorkoutEntryTests.swift`

- [ ] **Step 1.1: Write failing tests**

```swift
// JournalInsightTests/WorkoutEntryTests.swift
import Testing
import Foundation

@Suite("WorkoutEntryTests")
struct WorkoutEntryTests {

    @Test("WorkoutEntry initialises with defaults")
    func defaultInit() {
        let entry = WorkoutEntry(date: .now, source: .manual, durationSec: 3600)
        #expect(entry.exercises.isEmpty)
        #expect(entry.notes == nil)
        #expect(entry.garminActivityId == nil)
        #expect(entry.healthKitWorkoutId == nil)
    }

    @Test("WorkoutSource raw values are stable")
    func workoutSourceRawValues() {
        #expect(WorkoutSource.manual.rawValue == "manual")
        #expect(WorkoutSource.healthKit.rawValue == "healthKit")
        #expect(WorkoutSource.garmin.rawValue == "garmin")
    }

    @Test("LoggedExercise stores all fields")
    func loggedExercise() {
        let ex = LoggedExercise(name: "Bench Press", sets: 3, reps: 8, weightKg: 40.0, garminExerciseName: "BENCH_PRESS")
        #expect(ex.name == "Bench Press")
        #expect(ex.sets == 3)
        #expect(ex.reps == 8)
        #expect(ex.weightKg == 40.0)
        #expect(ex.garminExerciseName == "BENCH_PRESS")
    }
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```
Product > Test (⌘U) in Xcode, or:
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: compile error — `WorkoutEntry`, `WorkoutSource`, `LoggedExercise` not defined.

- [ ] **Step 1.3: Create WorkoutEntry.swift**

```swift
// JournalInsight/WorkoutEntry.swift
import Foundation
import SwiftData

// Minimal struct — expanded in SP3 with additional Garmin fields
struct LoggedExercise: Codable {
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    var garminExerciseName: String?   // validated Garmin catalogue name
}

enum WorkoutSource: String, Codable {
    case manual, healthKit, garmin
}

@Model
class WorkoutEntry {
    var date: Date
    var source: WorkoutSource
    var durationSec: Int
    var exercisesData: Data           // encoded [LoggedExercise]; avoid SwiftData Array<Codable> limitations
    var notes: String?
    var garminActivityId: Int64?
    var healthKitWorkoutId: UUID?

    // Computed accessor — encode/decode on demand
    var exercises: [LoggedExercise] {
        get {
            (try? JSONDecoder().decode([LoggedExercise].self, from: exercisesData)) ?? []
        }
        set {
            exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(date: Date, source: WorkoutSource, durationSec: Int,
         exercises: [LoggedExercise] = [],
         notes: String? = nil,
         garminActivityId: Int64? = nil,
         healthKitWorkoutId: UUID? = nil) {
        self.date = date
        self.source = source
        self.durationSec = durationSec
        self.exercisesData = (try? JSONEncoder().encode(exercises)) ?? Data()
        self.notes = notes
        self.garminActivityId = garminActivityId
        self.healthKitWorkoutId = healthKitWorkoutId
    }
}
```

- [ ] **Step 1.4: Run tests — expect pass**

- [ ] **Step 1.5: Commit**

```bash
git add JournalInsight/WorkoutEntry.swift JournalInsightTests/WorkoutEntryTests.swift
git commit -m "feat(sp1): add WorkoutEntry model + LoggedExercise + WorkoutSource"
```

---

## Task 2: TrainingStreakCalculator

**Files:**
- Create: `JournalInsight/Training/TrainingStreakCalculator.swift`
- Create: `JournalInsightTests/TrainingStreakCalculatorTests.swift`

- [ ] **Step 2.1: Create the Training/ directory and write failing tests**

```swift
// JournalInsightTests/TrainingStreakCalculatorTests.swift
import Testing
import Foundation

@Suite("TrainingStreakCalculatorTests")
struct TrainingStreakCalculatorTests {

    private func makeEntry(daysAgo: Int, source: WorkoutSource = .manual) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return WorkoutEntry(date: date, source: source, durationSec: 3600)
    }

    @Test("Returns 0 for empty entries")
    func emptyEntries() {
        #expect(TrainingStreakCalculator.currentStreak(from: []) == 0)
    }

    @Test("Returns 0 when no entry today")
    func noEntryToday() {
        let entries = [makeEntry(daysAgo: 1), makeEntry(daysAgo: 2)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 0)
    }

    @Test("Returns 1 when only today has entry")
    func onlyToday() {
        let entries = [makeEntry(daysAgo: 0)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 1)
    }

    @Test("Counts consecutive days including today")
    func consecutiveDays() {
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 1), makeEntry(daysAgo: 2)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 3)
    }

    @Test("Stops streak at gap")
    func breakInStreak() {
        // today + yesterday, then a gap, then 3 days before
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 1),
                       makeEntry(daysAgo: 3), makeEntry(daysAgo: 4)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("Multiple workouts same day count as one")
    func sameDay() {
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 0), makeEntry(daysAgo: 1)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("bestStreak returns 0 for empty")
    func bestStreakEmpty() {
        #expect(TrainingStreakCalculator.bestStreak(from: []) == 0)
    }

    @Test("bestStreak finds longest run")
    func bestStreakLongest() {
        // run of 3 then gap then run of 2
        let entries = [makeEntry(daysAgo: 10), makeEntry(daysAgo: 11), makeEntry(daysAgo: 12),
                       makeEntry(daysAgo: 15), makeEntry(daysAgo: 16)]
        #expect(TrainingStreakCalculator.bestStreak(from: entries) == 3)
    }
}
```

- [ ] **Step 2.2: Run tests — expect compile error**

- [ ] **Step 2.3: Create TrainingStreakCalculator.swift**

```swift
// JournalInsight/Training/TrainingStreakCalculator.swift
import Foundation

enum TrainingStreakCalculator {

    static func currentStreak(from entries: [WorkoutEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        guard days.contains(today) else { return 0 }
        var streak = 0
        var check = today
        while days.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check)!
        }
        return streak
    }

    static func bestStreak(from entries: [WorkoutEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 1, current = 1
        for i in 1 ..< days.count {
            let diff = cal.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            current = diff == 1 ? current + 1 : 1
            best = max(best, current)
        }
        return best
    }

    static let milestones: [Int] = [1, 3, 7, 14, 30, 60, 90]

    static func milestoneLabel(for days: Int) -> String {
        switch days {
        case 1:  return "First session back"
        case 3:  return "Three in a row"
        case 7:  return "One week consistent"
        case 14: return "Two weeks"
        case 30: return "One month"
        case 60: return "Two months"
        case 90: return "Three months"
        default: return "\(days) days"
        }
    }
}
```

- [ ] **Step 2.4: Run tests — expect pass**

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/Training/TrainingStreakCalculator.swift \
        JournalInsightTests/TrainingStreakCalculatorTests.swift
git commit -m "feat(sp1): add TrainingStreakCalculator with milestones"
```

---

## Task 3: Add WorkoutEntry to ModelContainer

**Files:**
- Modify: `JournalInsight/JournalInsightApp.swift`

- [ ] **Step 3.1: Open JournalInsightApp.swift**

Current ModelContainer line (around line 20):
```swift
.modelContainer(for: [JournalEntry.self, Goal.self, Tag.self])
```

- [ ] **Step 3.2: Add WorkoutEntry**

```swift
.modelContainer(for: [JournalEntry.self, Goal.self, Tag.self, WorkoutEntry.self])
```

- [ ] **Step 3.3: Build — expect no errors**

```
Product > Build (⌘B)
```

- [ ] **Step 3.4: Commit**

```bash
git add JournalInsight/JournalInsightApp.swift
git commit -m "feat(sp1): register WorkoutEntry in SwiftData ModelContainer"
```

---

## Task 4: Add .training WidgetType case

**Files:**
- Modify: `JournalInsight/MainScreenView.swift`

- [ ] **Step 4.1: Add .training to WidgetType enum**

Find the `WidgetType` enum (around line 17). Add the case:

```swift
enum WidgetType: String, Codable, CaseIterable {
    case streak, session, questions, calendar, goals, training  // ← add training

    var title: String {
        switch self {
        // ... existing cases ...
        case .training: return "Training"
        }
    }

    var systemImage: String {
        switch self {
        // ... existing cases ...
        case .training: return "figure.strengthtraining.traditional"
        }
    }
}
```

- [ ] **Step 4.2: Add routing in destinationView(for:)**

Find the `destinationView(for:)` function. Add:

```swift
case .training:
    TrainingDetailView()
```

- [ ] **Step 4.3: Add placeholder in WidgetCardView**

In `WidgetCardView`, find the switch on `widget.type` that renders compact content. Add:

```swift
case .training:
    TrainingWidgetView(size: widget.size)
```

`TrainingWidgetView` is created in Task 6. For now, add a placeholder that will compile:

```swift
case .training:
    VStack {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.title2)
        Text("Training")
            .font(.caption)
    }
```

- [ ] **Step 4.4: Build — expect no errors**

`TrainingDetailView` does not exist yet, so also add a temporary stub. Create `JournalInsight/Training/TrainingDetailView.swift`:

```swift
// Temporary stub — replaced fully in Task 7
import SwiftUI
struct TrainingDetailView: View {
    var body: some View { Text("Training — coming soon") }
}
```

- [ ] **Step 4.5: Run the app on simulator — verify .training appears in widget picker**

Add a new widget from the context menu: `.training` should appear as "Training" with the barbell icon.

- [ ] **Step 4.6: Commit**

```bash
git add JournalInsight/MainScreenView.swift JournalInsight/Training/TrainingDetailView.swift
git commit -m "feat(sp1): add .training WidgetType case + stub routing"
```

---

## Task 5: ManualWorkoutLogSheet

**Files:**
- Create: `JournalInsight/Training/ManualWorkoutLogSheet.swift`

- [ ] **Step 5.1: Create the file**

```swift
// JournalInsight/Training/ManualWorkoutLogSheet.swift
import SwiftUI
import SwiftData

struct ManualWorkoutLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = .now
    @State private var durationMin: Double = 45
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Workout date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("Duration") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(durationMin)) minutes")
                            .font(.headline)
                        Slider(value: $durationMin, in: 5...180, step: 5)
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let entry = WorkoutEntry(
            date: selectedDate,
            source: .manual,
            durationSec: Int(durationMin * 60),
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(entry)
        dismiss()
    }
}

#Preview {
    ManualWorkoutLogSheet()
        .modelContainer(for: WorkoutEntry.self, inMemory: true)
}
```

- [ ] **Step 5.2: Build — expect no errors**

- [ ] **Step 5.3: Commit**

```bash
git add JournalInsight/Training/ManualWorkoutLogSheet.swift
git commit -m "feat(sp1): add ManualWorkoutLogSheet"
```

---

## Task 6: TrainingWidgetView (compact card)

**Files:**
- Create: `JournalInsight/Training/TrainingWidgetView.swift`

- [ ] **Step 6.1: Create the file**

```swift
// JournalInsight/Training/TrainingWidgetView.swift
import SwiftUI
import SwiftData

struct TrainingWidgetView: View {
    let size: WidgetSize

    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]

    private var streak: Int { TrainingStreakCalculator.currentStreak(from: entries) }
    private var lastEntry: WorkoutEntry? { entries.first }

    private var daysSinceLabel: String {
        guard let last = lastEntry else { return "No workouts yet" }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        switch days {
        case 0: return "Trained today"
        case 1: return "Trained yesterday"
        default: return "\(days) days since last session"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
                Text("Training")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if streak > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(streak)")
                        .font(.title.weight(.bold))
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("0")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(daysSinceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, size == .small ? 0 : 4)
    }
}
```

- [ ] **Step 6.2: Replace the placeholder in MainScreenView.swift**

Find the `.training` case in the WidgetCardView switch and replace the placeholder:

```swift
case .training:
    TrainingWidgetView(size: widget.size)
```

- [ ] **Step 6.3: Build and run on simulator — verify widget shows streak or "No workouts yet"**

- [ ] **Step 6.4: Commit**

```bash
git add JournalInsight/Training/TrainingWidgetView.swift JournalInsight/MainScreenView.swift
git commit -m "feat(sp1): add TrainingWidgetView compact card"
```

---

## Task 7: TrainingDetailView (full screen)

**Files:**
- Modify: `JournalInsight/Training/TrainingDetailView.swift` (replaces stub from Task 4)

- [ ] **Step 7.1: Replace the stub**

```swift
// JournalInsight/Training/TrainingDetailView.swift
import SwiftUI
import SwiftData

struct TrainingDetailView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]
    @State private var showingLogSheet = false

    private var streak: Int { TrainingStreakCalculator.currentStreak(from: entries) }
    private var bestStreak: Int { TrainingStreakCalculator.bestStreak(from: entries) }

    private var nextMilestone: Int? {
        TrainingStreakCalculator.milestones.first { $0 > streak }
    }

    private var isMilestone: Bool {
        TrainingStreakCalculator.milestones.contains(streak)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Celebration banner on milestone
                if isMilestone && streak > 0 {
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(TrainingStreakCalculator.milestoneLabel(for: streak))
                            .font(.headline)
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .symbolEffect(.bounce, value: streak)
                }

                // Streak card
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current streak")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streak)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(streak == 1 ? "day" : "days")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Text("Best: \(bestStreak) days")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Progress to next milestone
                if let next = nextMilestone {
                    let progress = Double(streak) / Double(next)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next milestone: \(TrainingStreakCalculator.milestoneLabel(for: next))")
                            .font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .tint(.orange)
                        Text("\(next - streak) sessions to go")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Milestones list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Milestones")
                        .font(.headline)
                    ForEach(TrainingStreakCalculator.milestones, id: \.self) { m in
                        HStack {
                            Image(systemName: streak >= m ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(streak >= m ? .green : .secondary)
                            Text(TrainingStreakCalculator.milestoneLabel(for: m))
                            Spacer()
                            Text("\(m)d")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Recent workouts
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent workouts")
                            .font(.headline)
                        ForEach(entries.prefix(10)) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline.weight(.medium))
                                    Text("\(entry.durationSec / 60) min · \(entry.source.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !entry.exercises.isEmpty {
                                    Text("\(entry.exercises.count) exercises")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                // Log workout button
                Button {
                    showingLogSheet = true
                } label: {
                    Label("Log workout", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingLogSheet) {
            ManualWorkoutLogSheet()
        }
    }
}

#Preview {
    NavigationStack {
        TrainingDetailView()
    }
    .modelContainer(for: WorkoutEntry.self, inMemory: true)
}
```

- [ ] **Step 7.2: Build and run — tap Training widget → full screen opens, log a workout, verify streak increments**

- [ ] **Step 7.3: Commit**

```bash
git add JournalInsight/Training/TrainingDetailView.swift
git commit -m "feat(sp1): implement TrainingDetailView with streak, milestones, workout log"
```

---

## Task 8: Workout notification scheduling

**Files:**
- Modify: `JournalInsight/NotificationManager.swift`

- [ ] **Step 8.1: Add workout notification methods**

Open `NotificationManager.swift`. After `cancelReminder()`, add:

```swift
// Workout reminder — fires only on scheduled training days
static let workoutReminderIDPrefix = "workoutReminder_"

static func scheduleWorkoutReminder(weekdays: [Int], hour: Int, minute: Int, planSummary: String) {
    let center = UNUserNotificationCenter.current()
    // Remove all existing workout reminders before rescheduling
    center.removePendingNotificationRequests(withIdentifiers:
        (1...7).map { "\(workoutReminderIDPrefix)\($0)" })

    let content = UNMutableNotificationContent()
    content.sound = .default

    for weekday in weekdays {
        content.title = weekdayName(weekday) + " plan is ready"
        content.body = planSummary.isEmpty
            ? "Your training session is scheduled for today."
            : planSummary

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let id = "\(workoutReminderIDPrefix)\(weekday)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}

static func cancelWorkoutReminders() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: (1...7).map { "\(workoutReminderIDPrefix)\($0)" })
}

private static func weekdayName(_ weekday: Int) -> String {
    let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    return names.indices.contains(weekday) ? names[weekday] : "Today"
}
```

- [ ] **Step 8.2: Build — expect no errors**

- [ ] **Step 8.3: Commit**

```bash
git add JournalInsight/NotificationManager.swift
git commit -m "feat(sp1): add scheduleWorkoutReminder + cancelWorkoutReminders to NotificationManager"
```

---

## Task 9: Settings — Training section

**Files:**
- Modify: `JournalInsight/SettingsView.swift`

- [ ] **Step 9.1: Add AppStorage keys to AppTheme.swift**

Open `AppTheme.swift`, find `StorageKeys` enum, add:

```swift
static let workoutDays = "workoutDays"           // [Int] JSON-encoded
static let workoutReminderHour = "workoutReminderHour"     // Int
static let workoutReminderMinute = "workoutReminderMinute" // Int
static let workoutReminderEnabled = "workoutReminderEnabled" // Bool
```

- [ ] **Step 9.2: Add Training section to SettingsView**

In `SettingsView`, add state vars after the existing `@State private var showExportSheet`:

```swift
// Training settings
@AppStorage(StorageKeys.workoutReminderEnabled) private var workoutReminderEnabled: Bool = false
@AppStorage(StorageKeys.workoutReminderHour) private var workoutReminderHour: Int = 7
@AppStorage(StorageKeys.workoutReminderMinute) private var workoutReminderMinute: Int = 0
@State private var workoutDays: [Int] = []      // 1=Sun…7=Sat
```

Add `onAppear` modifier to load workoutDays:
```swift
.onAppear {
    nameField = userName
    // Load workout days from UserDefaults
    if let data = UserDefaults.standard.data(forKey: StorageKeys.workoutDays),
       let days = try? JSONDecoder().decode([Int].self, from: data) {
        workoutDays = days
    } else {
        workoutDays = [2, 5]  // Mon, Thu default
    }
}
```

Add before the closing `}` of the Form, after the Sync section:

```swift
// Training section
Section("Training") {
    // Workout days picker
    VStack(alignment: .leading, spacing: 8) {
        Text("Workout days")
            .font(.subheadline)
        HStack(spacing: 6) {
            ForEach(Array(zip([1,2,3,4,5,6,7], ["S","M","T","W","T","F","S"])), id: \.0) { day, label in
                let isSelected = workoutDays.contains(day)
                Button(label) {
                    if isSelected { workoutDays.removeAll { $0 == day } }
                    else { workoutDays.append(day) }
                    saveWorkoutDays()
                    rescheduleWorkoutReminders()
                }
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
                .font(.caption.weight(.semibold))
            }
        }
    }

    // Workout reminder time
    Toggle("Workout reminder", isOn: $workoutReminderEnabled)
        .onChange(of: workoutReminderEnabled) { _, enabled in
            if enabled {
                Task {
                    let granted = await NotificationManager.requestAuthorization()
                    if !granted { workoutReminderEnabled = false }
                    else { rescheduleWorkoutReminders() }
                }
            } else {
                NotificationManager.cancelWorkoutReminders()
            }
        }

    if workoutReminderEnabled {
        HStack {
            Text("Reminder time")
            Spacer()
            Picker("Hour", selection: $workoutReminderHour) {
                ForEach(4..<13, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.menu).labelsHidden()
            Text(":")
            Picker("Minute", selection: $workoutReminderMinute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.menu).labelsHidden()
        }
        .onChange(of: workoutReminderHour) { _, _ in rescheduleWorkoutReminders() }
        .onChange(of: workoutReminderMinute) { _, _ in rescheduleWorkoutReminders() }
    }

    // Garmin Connect placeholder (active in SP4)
    HStack {
        Label("Garmin Connect", systemImage: "applewatch")
        Spacer()
        Text("Connect in SP4")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

Add private helper methods to `SettingsView`:

```swift
private func saveWorkoutDays() {
    if let data = try? JSONEncoder().encode(workoutDays) {
        UserDefaults.standard.set(data, forKey: StorageKeys.workoutDays)
    }
}

private func rescheduleWorkoutReminders() {
    guard workoutReminderEnabled else { return }
    NotificationManager.scheduleWorkoutReminder(
        weekdays: workoutDays,
        hour: workoutReminderHour,
        minute: workoutReminderMinute,
        planSummary: ""    // populated in SP3/SP4
    )
}
```

- [ ] **Step 9.3: Build and run — open Settings, verify Training section is visible, tap workout days, verify they toggle orange**

- [ ] **Step 9.4: Commit**

```bash
git add JournalInsight/SettingsView.swift JournalInsight/AppTheme.swift
git commit -m "feat(sp1): add Training section to Settings (workout days, reminder, Garmin placeholder)"
```

---

## SP1 complete

Run full test suite (`⌘U`) — all existing tests must still pass. New tests for `TrainingStreakCalculator` and `WorkoutEntry` must pass.

```bash
git log --oneline -8
```

Expected commits:
```
feat(sp1): add Training section to Settings
feat(sp1): add scheduleWorkoutReminder + cancelWorkoutReminders
feat(sp1): implement TrainingDetailView with streak, milestones, workout log
feat(sp1): add TrainingWidgetView compact card
feat(sp1): add ManualWorkoutLogSheet
feat(sp1): add .training WidgetType case + stub routing
feat(sp1): register WorkoutEntry in SwiftData ModelContainer
feat(sp1): add TrainingStreakCalculator with milestones
feat(sp1): add WorkoutEntry model + LoggedExercise + WorkoutSource
```
