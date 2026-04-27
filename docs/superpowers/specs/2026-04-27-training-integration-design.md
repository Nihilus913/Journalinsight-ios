# Training Integration Design
**Date:** 2026-04-27
**Project:** JournalInsight iOS
**Status:** Approved for implementation planning

---

## Context

JournalInsight is an iOS 18.4 universal app (iPhone/iPad/macOS Catalyst) built with SwiftUI and SwiftData. Its purpose is behavioural — it serves as a trigger system for users with ADHD and similar executive-function challenges. Existing features include journaling, streaks, milestones, goals, notifications, and a customisable widget dashboard.

This spec extends the app to cover the full training workflow: surfacing health and recovery context, managing the training plan, auto-generating workout entries, and syncing with Garmin Connect — all framed around the same trigger principle: remove every decision that gives the ADHD brain an exit ramp.

### Core design principle

The app never says "you haven't trained." It only ever says what you *can do right now*. The plan is pre-adapted, the decisions are pre-made. The user's only question is: start or not.

Notifications are forward-looking ("Monday plan ready: Bench 3×8 @ 40kg") not backward-looking ("You missed 3 workouts this week"). The latter creates shame spirals. The former creates action.

---

## Sub-project roadmap

| SP | Name | Delivers |
|---|---|---|
| SP1 | Foundation | WorkoutEntry model, training streak, Training widget, workout-day notification |
| SP2 | HealthKit integration | Automatic workout entry creation, health context in widget |
| SP3a | Signal ingestion framework | Full HealthKit pipeline, signal normalisation, confidence scoring |
| SP3b | Composite assessment engine | Research-grounded readiness model, extensible signal registry |
| SP4 | Garmin Connect integration | OAuth, activity pull, plan push, bidirectional sync |

Each SP is independently deployable. SP2 runs before SP3a/b because HealthKit integration is needed for the signal pipeline. SP4 is last because it requires external OAuth and is the highest-complexity SP.

---

## Sync architecture (applies to SP2 + SP4)

### Core principle

The user never opens the app and waits for data. Sync happens in the background on a schedule and on meaningful triggers. The app always opens into a current state.

### Sync order

Order is strict — Garmin data must be fresh before the assessment engine runs:

1. **Garmin Connect sync** — pull latest activities, daily summaries, workout templates
2. **HealthKit read** — pull latest HRV, sleep, nutrition, steps, active calories
3. **SwiftData update** — write new `WorkoutEntry` records, update signal cache
4. **Assessment recalculation** — recompute `TrainingAssessment` with fresh signals
5. **Widget + notification refresh** — update Training widget, reschedule workout notification if plan changed

Steps 2–5 must not run with stale Garmin data. If Garmin sync fails (network unavailable, token expired), the app continues with the last successful Garmin snapshot and notes the staleness in the assessment confidence.

### Background sync mechanisms

| Mechanism | Used for | Frequency |
|---|---|---|
| `BGAppRefreshTask` | Full Garmin + HealthKit sync | iOS-scheduled, typically 1–4× per day based on usage patterns |
| `HKObserverQuery` + `enableBackgroundDelivery` | HealthKit new data notifications | Real-time, fires when YAZIO/Garmin writes new data to HealthKit |
| On app foreground | Full sync if last sync > 30 min ago | Every foreground transition after threshold |

`BGAppRefreshTask` is registered at app launch. iOS schedules it intelligently — the app cannot guarantee exact timing, but the system learns usage patterns and fires it ahead of typical open times.

`HKObserverQuery` covers HealthKit-native signals (HRV, sleep, nutrition). When YAZIO writes new nutrition data, the observer fires and triggers a HealthKit-only re-read (steps 2–4 above, skipping step 1 since Garmin data has not changed).

### Manual sync

Always available via a pull-to-refresh gesture on the Training screen and a "Sync now" button in Settings → Training. Manual sync runs the full 5-step sequence. A spinner is shown only for manual sync — background sync is silent.

Manual sync exists because Garmin's own sync to the Connect app is sometimes delayed. If the user knows they just completed a workout but the app hasn't received it yet, they can force a pull. This is a known limitation of the Garmin ecosystem, not a bug in JournalInsight.

### Failure handling

- **Garmin auth expired**: surface a non-blocking banner "Garmin session expired — tap to reconnect." Assessment runs on last known data, clearly marked as stale.
- **HealthKit permission revoked**: assessment omits affected signals, notes them as `.unavailable` in output.
- **Network unavailable**: sync skipped silently in background, retried on next foreground. Manual sync shows an error.
- **Partial sync** (Garmin succeeds, HealthKit stale): assessment runs, confidence scores reflect per-signal freshness.

---

## SP1 — Foundation

### WorkoutEntry model

A new SwiftData model, independent of `JournalEntry`:

```swift
@Model class WorkoutEntry {
    var date: Date
    var source: WorkoutSource        // .manual, .healthKit, .garmin
    var durationSec: Int
    var exercises: [LoggedExercise]  // populated in SP3/SP4; empty in SP1. LoggedExercise defined in SP3: name, sets, reps, weightKg, garminExerciseName
    var notes: String?
    var garminActivityId: Int64?     // populated in SP4
    var healthKitWorkoutId: UUID?    // populated in SP2
}

enum WorkoutSource: String, Codable {
    case manual, healthKit, garmin
}
```

`JournalEntry` and `WorkoutEntry` remain fully independent — neither references the other.

### Training streak

`StreakCalculator` gains a parallel method:

```swift
static func trainingStreak(from entries: [WorkoutEntry]) -> Int
static func bestTrainingStreak(from entries: [WorkoutEntry]) -> Int
```

Same consecutive-day logic as the journal streak. Operates on `WorkoutEntry.date`.

Training-specific milestones (separate from journal milestones):

| Milestone | Label |
|---|---|
| 1 | First session back |
| 3 | Three in a row |
| 7 | One week consistent |
| 14 | Two weeks |
| 30 | One month |
| 60 | Two months |
| 90 | Three months |

Milestone celebration uses the existing `showCelebration` animation pattern from `StreakDetailView` — no new animation system needed.

### Training widget

New `WidgetType` case: `.training`. Added to the existing `WidgetType` enum and widget grid.

Widget displays:
- Days since last workout (from most recent `WorkoutEntry`)
- Training streak count
- If today is a scheduled workout day: "Plan ready" label + "Start" chevron
- If not a workout day: next scheduled day

The widget never shows a guilt metric ("you haven't trained in X days" framed negatively). The days-since value is informational context, not an accusation.

### Workout-day notification

`NotificationManager` gains workout-specific scheduling:

```swift
static func scheduleWorkoutReminder(
    weekdays: [Int],       // 1=Sunday … 7=Saturday
    hour: Int,
    minute: Int,
    planSummary: String    // e.g. "Bench 3×8 @ 40kg · Row 3×8 @ 40kg · Shoulder 3×8 @ 10kg"
)
```

Content:
- **Title:** "Monday plan is ready"
- **Body:** First 2–3 exercises from the adapted plan (populated in SP3; placeholder text in SP1)
- **Sound:** default

The notification fires on scheduled workout days only. It never fires on rest days. It contains no negative framing.

### Manual workout log (SP1 stopgap)

A "Log workout" button in the Training widget and a simple sheet: date picker + duration slider + optional notes. Creates a `WorkoutEntry` with `source: .manual`. Replaced by automatic creation in SP2/SP4, but kept as a fallback permanently.

### Settings additions

New "Training" section in `SettingsView`:
- Workout days picker (multi-select weekdays)
- Workout reminder time (hour/minute, same UI pattern as journal reminder)
- Garmin Connect link (placeholder in SP1, active in SP4)

---

## SP2 — HealthKit integration

### Permissions

Request on first launch of Training features:
- `HKWorkoutType` (read) — detect completed workouts
- `HKQuantityType.heartRateVariabilitySDNN` (read)
- `HKQuantityType.restingHeartRate` (read)
- `HKQuantityType.stepCount` (read)
- `HKQuantityType.activeEnergyBurned` (read)
- `HKCategoryType.sleepAnalysis` (read)
- `HKQuantityType.dietaryEnergyConsumed` (read) — YAZIO writes here
- `HKQuantityType.dietaryProtein` (read)

Permissions are requested lazily (when the user first accesses a feature that needs them), not all at once on app launch.

### Automatic WorkoutEntry creation

`HealthKitObserver` monitors for new `HKWorkout` samples. When a strength training or fitness workout completes, it creates a `WorkoutEntry` with `source: .healthKit` and `healthKitWorkoutId` set. Duplicate prevention: check `healthKitWorkoutId` before inserting.

### Health context in Training widget

Widget gains a second display mode for workout days: shows the top 2 available recovery signals (e.g. sleep score, resting HR trend) as context below the plan summary. Signals shown only if data is available and fresh (< 24h). No signal = widget shows plan only, no placeholder text.

---

## SP3a — Signal ingestion framework

### Purpose

Normalise all available health signals into a common format for the assessment engine. The framework is the only part of the app that knows how to read raw HealthKit values. SP3b only consumes normalised `Signal` values.

### Signal model

```swift
struct Signal {
    let id: SignalID           // enum: .hrv, .restingHR, .sleepScore, .bodyBattery, ...
    let value: Double          // normalised 0.0–1.0
    let rawValue: Double       // original value with unit
    let unit: String
    let timestamp: Date
    let confidence: Confidence // .high, .medium, .low, .unavailable
    let source: SignalSource   // .healthKit, .garmin, .derived
}

enum Confidence { case high, medium, low, unavailable }
```

Confidence rules:
- `.high` — data from last 24h, sufficient sample count
- `.medium` — data from last 48h, or sparse samples
- `.low` — data older than 48h, or single sample
- `.unavailable` — no data

### Signal registry

A `SignalRegistry` holds the full catalogue of signals the app knows about. Each entry declares its source, normalisation function, and scientific reference. Adding a new signal = adding one entry to the registry. No other code changes required.

### Signals included at SP3a launch

| ID | Source | Normalisation basis |
|---|---|---|
| `.hrv` | HealthKit | User's 30-day baseline (z-score) |
| `.restingHR` | HealthKit | User's 30-day baseline (inverted z-score) |
| `.sleepScore` | Garmin via HealthKit | 0–100 → 0.0–1.0 |
| `.sleepDuration` | HealthKit | 6–9h optimal range |
| `.deepSleepRatio` | HealthKit | 15–25% of total sleep |
| `.bodyBattery` | Garmin direct API (SP4 required) | 0–100 → 0.0–1.0 |
| `.activeCalories7d` | HealthKit | % of TDEE estimate |
| `.caloricIntake7d` | HealthKit (YAZIO) | % of caloric goal |
| `.proteinIntake7d` | HealthKit (YAZIO) | g/kg bodyweight vs 1.6g/kg target |
| `.stepsTrend` | HealthKit | 7-day vs 30-day average ratio |
| `.daysSinceLastWorkout` | WorkoutEntry | 0 days = 1.0, >28 days = 0.0 |
| `.acwr` | WorkoutEntry | Acute:Chronic Workload Ratio (7d:28d volume) |

Additional signals are added as research is completed. The registry is the extension point — not the engine.

---

## SP3b — Composite assessment engine

### Safety-first design principles

1. **Transparent inputs** — every recommendation shows which signals contributed and their confidence level. The user sees the reasoning, not just the output.
2. **Conservative under uncertainty** — when confidence is low or signals conflict, the recommendation errs toward less load, not more.
3. **User override always available** — the user can dismiss or modify any recommendation. The app never prevents a workout.
4. **Not medical advice** — a permanent, visible disclaimer. Recommendations are training guidance, not clinical decisions.
5. **Research gate** — no signal weight is assigned without a cited scientific basis. The weight is stored alongside the reference.

### Research phase (prerequisite to SP3b implementation)

Before any assessment logic is written, each signal in the registry must have:
- A cited study supporting its relevance to training readiness
- A defined weight range (min/max contribution to composite)
- An edge-case definition (what happens when the signal is extreme or missing)

The existing `docs/research/energy-balance-sport-performance.md` (HealthTraining project, 20 references) covers nutrition × performance interactions. Additional literature is needed for HRV, sleep architecture, and ACWR. This research is a deliverable of SP3b, not an assumption.

### Assessment output

The engine produces a `TrainingAssessment`, not a score:

```swift
struct TrainingAssessment {
    let recommendation: Recommendation   // .proceed, .proceedWithCaution, .reduceLoad, .rest
    let planAdjustments: [PlanAdjustment] // e.g. reduce sets, reduce weight %, note recovery
    let contributingSignals: [SignalContribution]
    let disclaimer: String               // always present
    let generatedAt: Date
}

enum Recommendation {
    case proceed            // signals are positive, proceed as planned
    case proceedWithCaution // mixed signals, proceed but monitor
    case reduceLoad         // clear negative signals, reduce volume/intensity
    case rest               // strong negative signals across multiple dimensions
}
```

The recommendation is never "do not train" — it is always "here is the adjusted plan given today's context." Even `.rest` explains what lighter active recovery looks like.

### Nutrition as a composite factor

YAZIO writes dietary data to Apple Health. The engine reads `caloricIntake7d` and `proteinIntake7d` signals. Chronic underfueling (< ~80% of caloric goal over 7 days) and low protein (< 1.4g/kg/day) reduce the composite toward `.reduceLoad`. This is the dimension Garmin's own model cannot see. Scientific basis: RED-S literature (Mountjoy et al., 2014, 2018), protein synthesis research (Morton et al., 2018) — to be cited fully in the research phase.

### Detraining adjustment

Break duration is a `Signal` (`.daysSinceLastWorkout`). The plan adjustment for breaks is:

| Days off | Volume adjustment | Weight adjustment |
|---|---|---|
| < 7 | None | None |
| 7–13 | –1 set per exercise | None |
| 14–27 | –1 set, –10% weight | None |
| 28+ | –1 set, –15% weight | Recommend re-establishing form |

These thresholds are adjustable per-user based on observed response. They are defaults, not fixed rules. Scientific basis: detraining literature (Mujika & Padilla, 2000) — to be cited fully in research phase.

---

## SP4 — Garmin Connect integration

### Authentication

Garmin Connect uses OAuth 1.0a. The app uses `ASWebAuthenticationSession` for the OAuth flow. Tokens stored in iOS Keychain. Session refresh handled transparently.

### Pull: activity ingestion

Triggered by the sync architecture (BGAppRefreshTask, foreground threshold, or manual sync). Fetches recent activities from `/activitylist-service/activities/search/activities`. Strength training activities create or update `WorkoutEntry` records with `source: .garmin` and `garminActivityId` set. Exercise set detail fetched from `/activity-service/activity/{id}/exerciseSets`.

### Pull: daily metrics

Fetch Garmin daily summaries (Body Battery, steps, active calories, stress) to supplement HealthKit where HealthKit data is absent or lower quality. Garmin metrics that HealthKit already covers are not duplicated — HealthKit is the primary store, Garmin is supplementary.

### Push: workout plan sync

When the local training plan changes (exercise swap, weight update, substitution), the app pushes the updated workout to Garmin Connect via `connectapi('/workout-service/workout/{workoutId}', method: 'PUT', json: payload)`. This replicates the update flow confirmed working in the HealthTraining pipeline session of 2026-04-27.

Known constraint: Garmin exercise names must match Garmin's internal catalogue. Unknown exercise names are silently cleared by the API. The app maintains a local mapping of plan exercises to valid Garmin exercise name/category pairs, validated at push time.

### Exercise substitution in-app

When a user swaps an exercise (equipment unavailable, injury, preference), the app:
1. Updates the local plan
2. Suggests a substitution from a curated list mapped to the same muscle group
3. Shows the exercise via animation (GIF or video, sourced from a public exercise API)
4. Pushes the change to Garmin Connect

---

## What already exists in JournalInsight (no rebuild needed)

| Feature | File | Extension needed |
|---|---|---|
| Streak + milestones + celebration | `StreakDetailView.swift`, `StreakCalculator.swift` | Add `trainingStreak()` parallel method |
| Notification scheduling | `NotificationManager.swift` | Add `scheduleWorkoutReminder()` |
| Widget system + drag/resize | `MainScreenView.swift` | Add `.training` WidgetType case |
| Goals tracking | `Goal.swift`, `GoalsDetailView.swift` | Link training goals to WorkoutEntry completion |
| Settings (notifications, appearance) | `SettingsView.swift` | Add Training section |
| Data export | `DataExporter.swift` | Add WorkoutEntry export |

---

## Out of scope

- Building a proprietary strain score to replace Garmin/Apple Health scores
- Nutritional planning or meal suggestions
- Social or sharing features
- Apple Watch companion app
- Android

---

## Open questions (to resolve before SP3b implementation)

1. Which specific studies underpin each signal weight? (Research phase deliverable)
2. Does the app read Garmin Body Battery via HealthKit, or via direct Garmin API? (Garmin does not consistently write Body Battery to HealthKit — likely direct API required in SP4)
3. Per-user baseline calibration: how many days of data are needed before the composite is trusted enough to show? Suggested minimum: 14 days.
4. How does the app handle a user who has no HealthKit data at all (new iPhone, privacy restrictions)? Assessment engine must degrade gracefully to Garmin-only or plan-only mode.
