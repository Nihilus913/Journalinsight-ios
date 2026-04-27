# SP2 — HealthKit Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically create `WorkoutEntry` records when a workout completes in HealthKit, enable background sync, and surface recovery signals (sleep, RHR) in the Training widget on workout days.

**Architecture:** `HealthKitPermissions` declares the permission set. `HealthKitObserver` sets up `HKObserverQuery` for new workouts and triggers `WorkoutEntry` creation — deduplication via `healthKitWorkoutId`. `HealthKitReader` reads recovery signals (HRV, RHR, sleep, nutrition) for the widget. `BGAppRefreshTask` is registered at app launch to run the full sync cycle. SP2 does NOT implement the composite assessment engine (that is SP3b) — it only surfaces raw recovery values.

**Tech Stack:** HealthKit (`HKHealthStore`, `HKObserverQuery`, `HKAnchoredObjectQuery`), BackgroundTasks framework, SwiftData, Apple Testing framework.

**Prerequisite:** SP1 complete (WorkoutEntry model exists).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/HealthKit/HealthKitPermissions.swift` | Declares all HK type sets the app uses |
| Create | `JournalInsight/HealthKit/HealthKitObserver.swift` | Observes HKWorkout samples, auto-creates WorkoutEntry |
| Create | `JournalInsight/HealthKit/HealthKitReader.swift` | Reads sleep score, RHR, HRV for widget context |
| Create | `JournalInsight/HealthKit/BackgroundSyncManager.swift` | Registers + handles BGAppRefreshTask |
| Modify | `JournalInsight/JournalInsightApp.swift` | Register BGAppRefreshTask, start HKObserver on launch |
| Modify | `JournalInsight/Training/TrainingWidgetView.swift` | Show recovery context on workout days |
| Modify | `JournalInsight/Training/TrainingDetailView.swift` | Show "Auto-detected from HealthKit" badge on entries |
| Create | `JournalInsightTests/HealthKitReaderTests.swift` | Tests for HealthKitReader normalisation helpers |

**Info.plist keys required (add in Xcode target settings → Info):**
- `NSHealthShareUsageDescription` — "JournalInsight reads workout, sleep, heart rate, and nutrition data to provide training guidance."
- `NSHealthUpdateUsageDescription` — "JournalInsight does not write to HealthKit."
- `BGTaskSchedulerPermittedIdentifiers` — array containing `"com.journalinsight.backgroundSync"`

---

## Task 1: HealthKitPermissions

**Files:**
- Create: `JournalInsight/HealthKit/HealthKitPermissions.swift`

- [ ] **Step 1.1: Create the file**

```swift
// JournalInsight/HealthKit/HealthKitPermissions.swift
import HealthKit

enum HealthKitPermissions {

    // All types the app reads — requested together on first Training feature use
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.bodyMass),
        ]
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        return types
    }

    // App writes nothing to HealthKit
    static var writeTypes: Set<HKSampleType> { [] }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
}
```

- [ ] **Step 1.2: Build — expect no errors**

- [ ] **Step 1.3: Commit**

```bash
git add JournalInsight/HealthKit/HealthKitPermissions.swift
git commit -m "feat(sp2): add HealthKitPermissions type set"
```

---

## Task 2: HealthKitReader — recovery signals

**Files:**
- Create: `JournalInsight/HealthKit/HealthKitReader.swift`
- Create: `JournalInsightTests/HealthKitReaderTests.swift`

- [ ] **Step 2.1: Write tests for the pure helper that doesn't touch HK store**

```swift
// JournalInsightTests/HealthKitReaderTests.swift
import Testing
import Foundation

// HealthKitReader has a static normalisation helper for sleep duration
@Suite("HealthKitReaderTests")
struct HealthKitReaderTests {

    @Test("normaliseSleepScore maps 0-100 to 0-1")
    func normaliseSleepScore() {
        #expect(HealthKitReader.normaliseSleepScore(100) == 1.0)
        #expect(HealthKitReader.normaliseSleepScore(0) == 0.0)
        #expect(HealthKitReader.normaliseSleepScore(50) == 0.5)
    }

    @Test("normaliseSleepScore clamps out-of-range values")
    func normaliseSleepScoreClamped() {
        #expect(HealthKitReader.normaliseSleepScore(120) == 1.0)
        #expect(HealthKitReader.normaliseSleepScore(-10) == 0.0)
    }

    @Test("formattedRHR returns bpm string")
    func formattedRHR() {
        #expect(HealthKitReader.formattedRHR(62.0) == "62 bpm")
    }

    @Test("formattedRHR handles nil")
    func formattedRHRNil() {
        #expect(HealthKitReader.formattedRHR(nil) == "—")
    }
}
```

- [ ] **Step 2.2: Run tests — expect compile error (HealthKitReader not defined)**

- [ ] **Step 2.3: Create HealthKitReader.swift**

```swift
// JournalInsight/HealthKit/HealthKitReader.swift
import Foundation
import HealthKit

// Snapshot of latest recovery values — passed to TrainingWidgetView
struct RecoverySnapshot {
    var sleepScore: Double?        // 0–100 (Garmin writes to HK as metadata; often nil)
    var sleepDurationSec: Double?  // total sleep last night
    var deepSleepSec: Double?
    var restingHR: Double?         // bpm
    var hrv: Double?               // ms SDNN
    var lastUpdated: Date?
}

actor HealthKitReader {
    private let store: HKHealthStore

    init(store: HKHealthStore = .init()) {
        self.store = store
    }

    // MARK: — Public API

    func latestRecovery() async -> RecoverySnapshot {
        async let rhr = latestQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"))
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let (duration, deep) = latestSleep()

        let rhrVal = await rhr
        let hrvVal = await hrv
        let (sleepDur, sleepDeep) = await (duration, deep)

        return RecoverySnapshot(
            sleepDurationSec: sleepDur,
            deepSleepSec: sleepDeep,
            restingHR: rhrVal,
            hrv: hrvVal,
            lastUpdated: .now
        )
    }

    // MARK: — Normalisation helpers (static — testable without HK store)

    static func normaliseSleepScore(_ score: Double) -> Double {
        min(1.0, max(0.0, score / 100.0))
    }

    static func formattedRHR(_ bpm: Double?) -> String {
        guard let v = bpm else { return "—" }
        return "\(Int(v)) bpm"
    }

    // MARK: — Private

    private func latestQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let qtype = HKQuantityType(type)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: qtype,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                    end: .now),
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func latestSleep() async -> (duration: Double?, deep: Double?) {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                let total = samples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                           || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let deep = samples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: (total > 0 ? total : nil, deep > 0 ? deep : nil))
            }
            store.execute(query)
        }
    }
}
```

- [ ] **Step 2.4: Run tests — expect pass (pure static helpers test without HK store)**

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/HealthKit/HealthKitReader.swift JournalInsightTests/HealthKitReaderTests.swift
git commit -m "feat(sp2): add HealthKitReader + RecoverySnapshot with normalisation helpers"
```

---

## Task 3: HealthKitObserver — auto WorkoutEntry creation

**Files:**
- Create: `JournalInsight/HealthKit/HealthKitObserver.swift`

- [ ] **Step 3.1: Create the file**

```swift
// JournalInsight/HealthKit/HealthKitObserver.swift
import Foundation
import HealthKit
import SwiftData

// Observes for new HKWorkout samples and inserts WorkoutEntry records.
// Must be created once (typically in JournalInsightApp) and kept alive.
@MainActor
final class HealthKitObserver {
    private let store: HKHealthStore
    private let modelContext: ModelContext
    private var query: HKObserverQuery?

    init(store: HKHealthStore = .init(), modelContext: ModelContext) {
        self.store = store
        self.modelContext = modelContext
    }

    func start() {
        guard HealthKitPermissions.isAvailable else { return }
        let workoutType = HKObjectType.workoutType()

        query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            Task { @MainActor [weak self] in
                await self?.handleNewWorkouts()
                completionHandler()
            }
        }
        store.execute(query!)

        // Background delivery — system wakes app when new workout arrives
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    func stop() {
        if let q = query { store.stop(q); query = nil }
        store.disableAllBackgroundDelivery { _, _ in }
    }

    // MARK: — Private

    private func handleNewWorkouts() async {
        let anchor = loadAnchor()
        let workoutType = HKObjectType.workoutType()

        let (samples, newAnchor) = await withCheckedContinuation { (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Never>) in
            let query = HKAnchoredObjectQuery(
                type: workoutType, predicate: nil,
                anchor: anchor, limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, _ in
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(query)
        }

        for sample in samples.compactMap({ $0 as? HKWorkout }) {
            await insertIfNeeded(workout: sample)
        }

        if let newAnchor { saveAnchor(newAnchor) }
    }

    private func insertIfNeeded(workout: HKWorkout) async {
        let id = workout.uuid
        let descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.healthKitWorkoutId == id }
        )
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        let entry = WorkoutEntry(
            date: workout.startDate,
            source: .healthKit,
            durationSec: Int(workout.duration),
            healthKitWorkoutId: id
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    // Anchor persisted in UserDefaults so we only process new workouts across launches
    private static let anchorKey = "hkWorkoutAnchor"

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: Self.anchorKey)
    }
}
```

- [ ] **Step 3.2: Build — expect no errors**

- [ ] **Step 3.3: Commit**

```bash
git add JournalInsight/HealthKit/HealthKitObserver.swift
git commit -m "feat(sp2): add HealthKitObserver — auto WorkoutEntry on new HKWorkout"
```

---

## Task 4: BackgroundSyncManager

**Files:**
- Create: `JournalInsight/HealthKit/BackgroundSyncManager.swift`

- [ ] **Step 4.1: Create the file**

```swift
// JournalInsight/HealthKit/BackgroundSyncManager.swift
import Foundation
import BackgroundTasks

// Identifier must match BGTaskSchedulerPermittedIdentifiers in Info.plist
let kBGSyncTaskIdentifier = "com.journalinsight.backgroundSync"

enum BackgroundSyncManager {

    // Call from application(_:didFinishLaunchingWithOptions:) or @main init
    static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kBGSyncTaskIdentifier, using: nil) { task in
            handleSync(task: task as! BGAppRefreshTask)
        }
    }

    // Schedule next background refresh — call after every sync completes
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: kBGSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // at least 1 hour out
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: — Private

    private static func handleSync(task: BGAppRefreshTask) {
        scheduleNext()  // reschedule immediately
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // In SP2, only HealthKit step runs (Garmin is SP4)
        // The observer handles new workouts reactively; here we schedule the next refresh
        task.setTaskCompleted(success: true)
    }
}
```

- [ ] **Step 4.2: Build — expect no errors**

- [ ] **Step 4.3: Commit**

```bash
git add JournalInsight/HealthKit/BackgroundSyncManager.swift
git commit -m "feat(sp2): add BackgroundSyncManager with BGAppRefreshTask registration"
```

---

## Task 5: Wire up in JournalInsightApp

**Files:**
- Modify: `JournalInsight/JournalInsightApp.swift`

- [ ] **Step 5.1: Add BackgroundTasks import + registration**

In `JournalInsightApp.swift`, after the existing imports add:

```swift
import BackgroundTasks
import HealthKit
```

- [ ] **Step 5.2: Add @State for HKHealthStore and observer**

Inside the `@main struct JournalInsightApp`:

```swift
@State private var healthStore = HKHealthStore()
@State private var hkObserver: HealthKitObserver?
```

- [ ] **Step 5.3: Register BGTask and start observer**

Add `.onAppear` to the `WindowGroup` body, or use `init()`:

```swift
var body: some Scene {
    WindowGroup {
        MainScreenView()
            // ... existing modifiers ...
            .task {
                // Register background task
                BackgroundSyncManager.registerTasks()
                BackgroundSyncManager.scheduleNext()
            }
    }
    .modelContainer(for: [JournalEntry.self, Goal.self, Tag.self, WorkoutEntry.self]) { result in
        if case .success(let container) = result {
            // Start HealthKit observer once model context is ready
            let context = container.mainContext
            let observer = HealthKitObserver(store: healthStore, modelContext: context)
            hkObserver = observer

            // Request permissions then start observer
            Task {
                if HealthKitPermissions.isAvailable {
                    try? await healthStore.requestAuthorization(
                        toShare: HealthKitPermissions.writeTypes,
                        read: HealthKitPermissions.readTypes
                    )
                    await observer.start()
                }
            }
        }
    }
}
```

> **Note:** The `.modelContainer` modifier accepts a result handler closure in some versions. If your Xcode version requires a different pattern, wire the observer in `MainScreenView.onAppear` using `@Environment(\.modelContext)` instead. The essential logic is the same: after the container is ready, create `HealthKitObserver(modelContext:)` and call `start()`.

- [ ] **Step 5.4: Add Info.plist keys in Xcode**

In Xcode, select the JournalInsight target → Info tab → add:
- Key: `NSHealthShareUsageDescription`, Value: `"JournalInsight reads workout, sleep, heart rate, and nutrition data to provide training guidance."`
- Key: `BGTaskSchedulerPermittedIdentifiers`, Type: Array, Item 0: `"com.journalinsight.backgroundSync"`

- [ ] **Step 5.5: Build and run on a real device (HealthKit requires real device)**

Open Settings → Privacy → Health → JournalInsight. Verify permissions requested. Complete a workout in the Fitness app and verify a new `WorkoutEntry` appears in Training tab within a minute.

> **Simulator testing note:** HK observer notifications don't fire on simulator. Use `HKHealthStore().save(_:withCompletion:)` in a debug helper to inject a test workout, or test on device.

- [ ] **Step 5.6: Commit**

```bash
git add JournalInsight/JournalInsightApp.swift
git commit -m "feat(sp2): wire HealthKitObserver + BackgroundSyncManager at app launch"
```

---

## Task 6: Recovery context in Training widget

**Files:**
- Modify: `JournalInsight/Training/TrainingWidgetView.swift`

- [ ] **Step 6.1: Add recovery data display for workout days**

The widget should show sleep + RHR when today is a scheduled workout day. Add an async fetch:

```swift
// TrainingWidgetView.swift — add at the top of the struct body
@State private var recovery: RecoverySnapshot? = nil
@AppStorage(StorageKeys.workoutDays) private var workoutDaysData: Data = Data()

private var isWorkoutDay: Bool {
    guard let days = try? JSONDecoder().decode([Int].self, from: workoutDaysData) else { return false }
    let weekday = Calendar.current.component(.weekday, from: .now)
    return days.contains(weekday)
}
```

Add after the existing `daysSinceLabel` display in the body:

```swift
// Show recovery context only on workout days and only if we have data
if isWorkoutDay, let r = recovery {
    Divider()
    HStack(spacing: 12) {
        if let dur = r.sleepDurationSec {
            Label(String(format: "%.0fh sleep", dur / 3600), systemImage: "moon.zzz")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let rhr = r.restingHR {
            Label("\(Int(rhr)) bpm", systemImage: "heart")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

Add `.task` modifier to the VStack to load recovery data:

```swift
.task {
    if isWorkoutDay && HealthKitPermissions.isAvailable {
        let reader = HealthKitReader()
        recovery = await reader.latestRecovery()
    }
}
```

- [ ] **Step 6.2: Build and run — on a workout day, widget should show sleep + RHR context**

- [ ] **Step 6.3: Commit**

```bash
git add JournalInsight/Training/TrainingWidgetView.swift
git commit -m "feat(sp2): show recovery context (sleep, RHR) in Training widget on workout days"
```

---

## Task 7: Source badge in TrainingDetailView

**Files:**
- Modify: `JournalInsight/Training/TrainingDetailView.swift`

- [ ] **Step 7.1: Update the recent workouts list to show source badge**

Find the entry list section in `TrainingDetailView`. Replace the source text:

```swift
// Replace:
Text("\(entry.durationSec / 60) min · \(entry.source.rawValue)")
    .font(.caption).foregroundStyle(.secondary)

// With:
HStack(spacing: 6) {
    Text("\(entry.durationSec / 60) min")
        .font(.caption).foregroundStyle(.secondary)
    Label(entry.source.rawValue, systemImage: entry.source.icon)
        .font(.caption2)
        .foregroundStyle(entry.source.color)
}
```

Add computed properties to `WorkoutSource` in `WorkoutEntry.swift`:

```swift
extension WorkoutSource {
    var icon: String {
        switch self {
        case .manual:    return "pencil"
        case .healthKit: return "heart.fill"
        case .garmin:    return "applewatch"
        }
    }

    var color: Color {
        switch self {
        case .manual:    return .orange
        case .healthKit: return .red
        case .garmin:    return .blue
        }
    }
}
```

- [ ] **Step 7.2: Build — add `import SwiftUI` to WorkoutEntry.swift if needed**

- [ ] **Step 7.3: Run tests — all pass**

- [ ] **Step 7.4: Commit**

```bash
git add JournalInsight/WorkoutEntry.swift JournalInsight/Training/TrainingDetailView.swift
git commit -m "feat(sp2): show source badge (manual/HealthKit/Garmin) on workout entries"
```

---

## SP2 complete

Run full test suite (`⌘U`) — all existing and new tests must pass.

```bash
git log --oneline -8
```

Expected commits:
```
feat(sp2): show source badge (manual/HealthKit/Garmin) on workout entries
feat(sp2): show recovery context (sleep, RHR) in Training widget on workout days
feat(sp2): wire HealthKitObserver + BackgroundSyncManager at app launch
feat(sp2): add BackgroundSyncManager with BGAppRefreshTask registration
feat(sp2): add HealthKitObserver — auto WorkoutEntry on new HKWorkout
feat(sp2): add HealthKitReader + RecoverySnapshot with normalisation helpers
feat(sp2): add HealthKitPermissions type set
```
