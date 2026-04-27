# SP3a — Signal Ingestion Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define a typed, normalised `Signal` model and a `SignalIngester` that reads all available health data sources into a uniform 0–1 value with confidence scoring — ready for SP3b's assessment engine.

**Architecture:** `Signal` is a pure value type. `SignalNormaliser` contains all normalisation math (pure functions, fully testable). `SignalRegistry` catalogues every known signal with metadata (source, normalisation basis, scientific reference placeholder). `SignalIngester` is the single entry point that reads HealthKit + WorkoutEntry and produces `[Signal]` — it depends on `HealthKitReader` (SP2). No SwiftData models are created in SP3a; signals are computed on demand.

**Tech Stack:** Swift actors, HealthKit, SwiftData (read-only, via WorkoutEntry), Apple Testing framework.

**Prerequisites:** SP1 (WorkoutEntry model), SP2 (HealthKitReader, HealthKitPermissions).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Assessment/Signal.swift` | Signal value type, SignalID enum, Confidence enum, SignalSource enum, TrendDirection enum |
| Create | `JournalInsight/Assessment/SignalNormaliser.swift` | Pure normalisation functions, one per signal type |
| Create | `JournalInsight/Assessment/SignalRegistry.swift` | Catalogue of all known signals with metadata |
| Create | `JournalInsight/Assessment/SignalIngester.swift` | Reads HK + WorkoutEntry, produces [Signal] |
| Create | `JournalInsightTests/SignalNormaliserTests.swift` | Tests for all normalisation functions |
| Create | `JournalInsightTests/SignalIngesterTests.swift` | Tests for confidence logic and ingester output shape |

---

## Task 1: Signal model types

**Files:**
- Create: `JournalInsight/Assessment/Signal.swift`
- Create: `JournalInsightTests/SignalNormaliserTests.swift` (partial — adds more in Task 2)

- [ ] **Step 1.1: Write failing tests for Signal construction**

```swift
// JournalInsightTests/SignalNormaliserTests.swift
import Testing
import Foundation

@Suite("SignalTests")
struct SignalTests {

    @Test("Signal clamps normalised value to 0–1")
    func clampedValue() {
        let s = Signal(id: .hrv, normalisedValue: 1.5, rawValue: 200, unit: "ms",
                       timestamp: .now, confidence: .high, source: .healthKit)
        #expect(s.value == 1.0)
    }

    @Test("Signal stores negative clamped to 0")
    func clampedNegative() {
        let s = Signal(id: .restingHR, normalisedValue: -0.1, rawValue: 40, unit: "bpm",
                       timestamp: .now, confidence: .low, source: .healthKit)
        #expect(s.value == 0.0)
    }

    @Test("Confidence unavailable when no data")
    func unavailableConfidence() {
        let s = Signal(id: .sleepScore, normalisedValue: 0, rawValue: 0, unit: "",
                       timestamp: .distantPast, confidence: .unavailable, source: .healthKit)
        #expect(s.confidence == .unavailable)
    }
}
```

- [ ] **Step 1.2: Run — expect compile error**

- [ ] **Step 1.3: Create Signal.swift**

```swift
// JournalInsight/Assessment/Signal.swift
import Foundation

enum SignalID: String, CaseIterable, Codable {
    case hrv                  // HRV SDNN ms — HealthKit
    case restingHR            // resting heart rate bpm — HealthKit (lower = better)
    case sleepScore           // 0–100 — Garmin writes via HealthKit metadata
    case sleepDuration        // seconds — HealthKit (optimal 6–9h)
    case deepSleepRatio       // deep/total — HealthKit (optimal 0.15–0.25)
    case bodyBattery          // 0–100 — Garmin direct API (SP4 required)
    case activeCalories7d     // 7d sum active kcal — HealthKit
    case caloricIntake7d      // 7d avg consumed kcal as % of goal — HealthKit/YAZIO
    case proteinIntake7d      // 7d avg protein g/kg bodyweight — HealthKit/YAZIO
    case stepsTrend           // 7d vs 30d average steps ratio — HealthKit
    case daysSinceLastWorkout // 0 = today, 28+ = floor — WorkoutEntry
    case acwr                 // Acute:Chronic Workload Ratio (7d:28d) — WorkoutEntry
}

enum Confidence: Int, Comparable, Codable {
    case unavailable = 0  // no data
    case low         = 1  // data > 48h old, or single sample
    case medium      = 2  // data 24–48h old, or sparse samples
    case high        = 3  // data < 24h, sufficient samples

    static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SignalSource: String, Codable {
    case healthKit
    case garmin         // Garmin direct API (SP4 required)
    case derived        // computed from WorkoutEntry records
}

enum TrendDirection: String, Codable {
    case up, down, flat
}

struct Signal: Identifiable, Codable {
    let id: SignalID
    /// Normalised value: 0.0 (bad/low) → 1.0 (optimal), clamped on init.
    let value: Double
    /// Original value in source units (for display)
    let rawValue: Double
    let unit: String
    let timestamp: Date
    let confidence: Confidence
    let source: SignalSource

    init(id: SignalID, normalisedValue: Double, rawValue: Double, unit: String,
         timestamp: Date, confidence: Confidence, source: SignalSource) {
        self.id = id
        self.value = min(1.0, max(0.0, normalisedValue))
        self.rawValue = rawValue
        self.unit = unit
        self.timestamp = timestamp
        self.confidence = confidence
        self.source = source
    }
}
```

- [ ] **Step 1.4: Run tests — expect pass**

- [ ] **Step 1.5: Commit**

```bash
git add JournalInsight/Assessment/Signal.swift JournalInsightTests/SignalNormaliserTests.swift
git commit -m "feat(sp3a): add Signal model — SignalID, Confidence, SignalSource, TrendDirection"
```

---

## Task 2: SignalNormaliser — pure math

**Files:**
- Create: `JournalInsight/Assessment/SignalNormaliser.swift`
- Modify: `JournalInsightTests/SignalNormaliserTests.swift` (add normalisation tests)

- [ ] **Step 2.1: Add normalisation tests**

Append to `SignalNormaliserTests.swift`:

```swift
@Suite("SignalNormaliserTests")
struct SignalNormaliserTests {

    // HRV: z-score against baseline; higher is better
    @Test("HRV above baseline normalises > 0.5")
    func hrvAboveBaseline() {
        // baseline mean=50ms sd=10ms, current=60ms → z=+1
        let n = SignalNormaliser.normaliseHRV(current: 60, baselineMean: 50, baselineSD: 10)
        #expect(n > 0.5)
        #expect(n <= 1.0)
    }

    @Test("HRV at baseline normalises to 0.5")
    func hrvAtBaseline() {
        let n = SignalNormaliser.normaliseHRV(current: 50, baselineMean: 50, baselineSD: 10)
        #expect(abs(n - 0.5) < 0.01)
    }

    // RHR: inverted z-score; lower is better
    @Test("RHR below baseline normalises > 0.5")
    func rhrBelowBaseline() {
        // baseline mean=65bpm sd=5, current=60 → z=-1 (good)
        let n = SignalNormaliser.normaliseRestingHR(current: 60, baselineMean: 65, baselineSD: 5)
        #expect(n > 0.5)
    }

    @Test("RHR above baseline normalises < 0.5")
    func rhrAboveBaseline() {
        let n = SignalNormaliser.normaliseRestingHR(current: 70, baselineMean: 65, baselineSD: 5)
        #expect(n < 0.5)
    }

    // Sleep duration: tent function, optimal 7.5h (27000s)
    @Test("Sleep duration at 7.5h gives 1.0")
    func sleepOptimal() {
        let n = SignalNormaliser.normaliseSleepDuration(seconds: 7.5 * 3600)
        #expect(abs(n - 1.0) < 0.01)
    }

    @Test("Sleep duration at 5h gives < 0.5")
    func sleepShort() {
        let n = SignalNormaliser.normaliseSleepDuration(seconds: 5 * 3600)
        #expect(n < 0.5)
    }

    // Caloric intake ratio: optimal 0.8–1.1
    @Test("Caloric ratio in optimal range gives 1.0")
    func caloricRatioOptimal() {
        let n = SignalNormaliser.normaliseCaloricRatio(ratio: 0.95)
        #expect(abs(n - 1.0) < 0.01)
    }

    @Test("Caloric ratio 0.5 (underfueling) gives < 0.5")
    func caloricRatioUnderfueling() {
        let n = SignalNormaliser.normaliseCaloricRatio(ratio: 0.5)
        #expect(n < 0.5)
    }

    @Test("Caloric ratio 1.5 (excess) gives < 0.75")
    func caloricRatioExcess() {
        let n = SignalNormaliser.normaliseCaloricRatio(ratio: 1.5)
        #expect(n < 0.75)
    }

    // Protein g/kg: optimal ≥2.0 g/kg
    @Test("Protein 2.0 g/kg normalises to 1.0")
    func proteinOptimal() {
        let n = SignalNormaliser.normaliseProteinPerKg(gPerKg: 2.0)
        #expect(abs(n - 1.0) < 0.01)
    }

    @Test("Protein 1.0 g/kg normalises to 0.5")
    func proteinLow() {
        let n = SignalNormaliser.normaliseProteinPerKg(gPerKg: 1.0)
        #expect(n < 0.6)
    }

    // ACWR: tent function, optimal 0.8–1.1
    @Test("ACWR 1.0 normalises to 1.0")
    func acwrOptimal() {
        let n = SignalNormaliser.normaliseACWR(acwr: 1.0)
        #expect(abs(n - 1.0) < 0.01)
    }

    @Test("ACWR 1.5 (overload) normalises < 0.5")
    func acwrHigh() {
        let n = SignalNormaliser.normaliseACWR(acwr: 1.5)
        #expect(n < 0.5)
    }

    @Test("ACWR 0.3 (detraining) normalises < 0.5")
    func acwrLow() {
        let n = SignalNormaliser.normaliseACWR(acwr: 0.3)
        #expect(n < 0.5)
    }

    // Days since last workout: 0 days = 1.0, 28+ = 0.0
    @Test("0 days since workout = 1.0")
    func daysSinceFresh() {
        #expect(SignalNormaliser.normaliseDaysSinceWorkout(days: 0) == 1.0)
    }

    @Test("28 days since workout = 0.0")
    func daysSinceDetraining() {
        #expect(SignalNormaliser.normaliseDaysSinceWorkout(days: 28) == 0.0)
    }
}
```

- [ ] **Step 2.2: Run — expect compile error (SignalNormaliser not defined)**

- [ ] **Step 2.3: Create SignalNormaliser.swift**

```swift
// JournalInsight/Assessment/SignalNormaliser.swift
import Foundation

// All functions return 0.0–1.0 where 1.0 is optimal.
// Higher is always better — inverted where necessary.
enum SignalNormaliser {

    // MARK: — HRV (higher is better)
    // Sigmoid mapping via z-score: z = (current - mean) / sd
    // Output: 0.5 at mean, saturates toward 1.0 at +2 SD, toward 0.0 at -2 SD
    static func normaliseHRV(current: Double, baselineMean: Double, baselineSD: Double) -> Double {
        guard baselineSD > 0 else { return 0.5 }
        let z = (current - baselineMean) / baselineSD
        return sigmoid(z)
    }

    // MARK: — Resting HR (lower is better → inverted z-score)
    static func normaliseRestingHR(current: Double, baselineMean: Double, baselineSD: Double) -> Double {
        guard baselineSD > 0 else { return 0.5 }
        let z = (baselineMean - current) / baselineSD  // inverted: lower than baseline = positive z
        return sigmoid(z)
    }

    // MARK: — Sleep duration (tent function, optimal 6.5–8h)
    // Peaks at 7.5h (27000s), drops linearly outside 6h–9h, clamps to 0 outside 4h–10h
    static func normaliseSleepDuration(seconds: Double) -> Double {
        let hours = seconds / 3600
        let optimal = 7.5
        let low = 6.0, high = 9.0, floor = 4.0, ceiling = 10.0
        if hours < floor || hours > ceiling { return 0.0 }
        if hours >= low && hours <= high {
            // Tent peak: 1.0 at optimal, linear ramp within band
            let dist = abs(hours - optimal)
            let halfBand = (high - low) / 2.0
            return max(0.0, 1.0 - dist / halfBand * 0.2)  // small penalty within optimal band
        }
        if hours < low { return (hours - floor) / (low - floor) }
        return (ceiling - hours) / (ceiling - high)
    }

    // MARK: — Deep sleep ratio (optimal 0.15–0.25)
    static func normaliseDeepSleepRatio(ratio: Double) -> Double {
        let optimal = 0.20
        let low = 0.15, high = 0.25
        if ratio < 0.05 || ratio > 0.40 { return 0.0 }
        if ratio >= low && ratio <= high { return 1.0 }
        if ratio < low { return ratio / low }
        return 1.0 - (ratio - high) / (0.40 - high)
    }

    // MARK: — Caloric intake ratio (consumed / goal)
    // Optimal 0.80–1.10; below 0.5 = severe underfueling; above 1.5 = notable surplus
    // Based on HealthTraining constants: _PROGRESS_KCAL_RATIO_MIN=0.80, MAX=1.10
    static func normaliseCaloricRatio(ratio: Double) -> Double {
        let lo = 0.80, hi = 1.10
        if ratio < 0 { return 0.0 }
        if ratio >= lo && ratio <= hi { return 1.0 }
        if ratio < lo { return max(0, ratio / lo) }
        // Above target: gently penalise surplus
        return max(0, 1.0 - (ratio - hi) / 0.5)
    }

    // MARK: — Protein per kg bodyweight
    // Optimal ≥ 2.0 g/kg (HealthTraining: _PROGRESS_PROTEIN_PER_KG = 2.0)
    // Linear 0→1 from 0 to 2.0 g/kg, capped at 1.0
    static func normaliseProteinPerKg(gPerKg: Double) -> Double {
        min(1.0, max(0.0, gPerKg / 2.0))
    }

    // MARK: — ACWR (Acute:Chronic Workload Ratio)
    // Optimal 0.8–1.1; below 0.5 = detraining; above 1.3 = overload risk
    // Reference: Gabbett 2016 (training load and injury risk)
    static func normaliseACWR(acwr: Double) -> Double {
        let lo = 0.8, hi = 1.1, min_ = 0.0, max_ = 1.5
        if acwr < min_ || acwr > max_ { return 0.0 }
        if acwr >= lo && acwr <= hi { return 1.0 }
        if acwr < lo { return acwr / lo }
        return max(0, 1.0 - (acwr - hi) / (max_ - hi))
    }

    // MARK: — Days since last workout
    // 0 = trained today (1.0), 28+ = detraining floor (0.0)
    static func normaliseDaysSinceWorkout(days: Int) -> Double {
        if days <= 0 { return 1.0 }
        if days >= 28 { return 0.0 }
        return 1.0 - Double(days) / 28.0
    }

    // MARK: — Steps trend (7d vs 30d ratio)
    // 1.0 when 7d avg ≥ 30d avg; down to 0 at 50% of 30d avg
    static func normaliseStepsTrend(ratio: Double) -> Double {
        min(1.0, max(0.0, (ratio - 0.5) / 0.5))
    }

    // MARK: — Body battery (Garmin, 0–100 → 0–1)
    static func normaliseBodyBattery(_ value: Double) -> Double {
        min(1.0, max(0.0, value / 100.0))
    }

    // MARK: — Private helpers

    private static func sigmoid(_ z: Double) -> Double {
        1.0 / (1.0 + exp(-z))
    }
}
```

- [ ] **Step 2.4: Run tests — expect pass**

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/Assessment/SignalNormaliser.swift JournalInsightTests/SignalNormaliserTests.swift
git commit -m "feat(sp3a): add SignalNormaliser — normalisation functions for all 12 signal types"
```

---

## Task 3: SignalRegistry

**Files:**
- Create: `JournalInsight/Assessment/SignalRegistry.swift`

- [ ] **Step 3.1: Create the file**

```swift
// JournalInsight/Assessment/SignalRegistry.swift
import Foundation

struct SignalMeta {
    let id: SignalID
    let displayName: String
    let unit: String
    let source: SignalSource
    let normalisationBasis: String   // human-readable description
    let scientificReference: String  // citation or "pending research phase"
}

enum SignalRegistry {

    static let all: [SignalID: SignalMeta] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.id, $0) }
    )

    static let entries: [SignalMeta] = [
        SignalMeta(
            id: .hrv,
            displayName: "HRV",
            unit: "ms",
            source: .healthKit,
            normalisationBasis: "Z-score vs user 30-day baseline",
            scientificReference: "Plews et al. 2013 — HRV as readiness marker"
        ),
        SignalMeta(
            id: .restingHR,
            displayName: "Resting HR",
            unit: "bpm",
            source: .healthKit,
            normalisationBasis: "Inverted z-score vs user 30-day baseline",
            scientificReference: "Buchheit 2014 — RHR elevations indicate incomplete recovery"
        ),
        SignalMeta(
            id: .sleepScore,
            displayName: "Sleep Score",
            unit: "",
            source: .healthKit,
            normalisationBasis: "0–100 → 0.0–1.0 linear",
            scientificReference: "Garmin sleep scoring algorithm (proprietary)"
        ),
        SignalMeta(
            id: .sleepDuration,
            displayName: "Sleep Duration",
            unit: "hours",
            source: .healthKit,
            normalisationBasis: "Tent function; optimal 6.5–8h, peaks at 7.5h",
            scientificReference: "Watson et al. 2015 — 7–9h sleep for athletes"
        ),
        SignalMeta(
            id: .deepSleepRatio,
            displayName: "Deep Sleep Ratio",
            unit: "%",
            source: .healthKit,
            normalisationBasis: "Tent function; optimal 15–25% of total sleep",
            scientificReference: "Dattilo et al. 2011 — deep sleep and muscle recovery"
        ),
        SignalMeta(
            id: .bodyBattery,
            displayName: "Body Battery",
            unit: "",
            source: .garmin,
            normalisationBasis: "0–100 → 0.0–1.0 linear (Garmin direct API, SP4)",
            scientificReference: "Garmin proprietary composite stress-recovery metric"
        ),
        SignalMeta(
            id: .activeCalories7d,
            displayName: "Active Calories 7d",
            unit: "kcal/day",
            source: .healthKit,
            normalisationBasis: "% of estimated TDEE, sigmoid",
            scientificReference: "Pending research phase"
        ),
        SignalMeta(
            id: .caloricIntake7d,
            displayName: "Caloric Intake 7d",
            unit: "% of goal",
            source: .healthKit,
            normalisationBasis: "Optimal 80–110% of goal (HealthTraining constants)",
            scientificReference: "Mountjoy et al. 2014 — RED-S and underfueling"
        ),
        SignalMeta(
            id: .proteinIntake7d,
            displayName: "Protein 7d",
            unit: "g/kg",
            source: .healthKit,
            normalisationBasis: "Linear 0→1.0 from 0 to 2.0 g/kg",
            scientificReference: "Morton et al. 2018 — 1.62g/kg sufficient, 2.0g/kg safe ceiling"
        ),
        SignalMeta(
            id: .stepsTrend,
            displayName: "Steps Trend",
            unit: "ratio",
            source: .healthKit,
            normalisationBasis: "7d avg / 30d avg; optimal ≥ 1.0",
            scientificReference: "Pending research phase"
        ),
        SignalMeta(
            id: .daysSinceLastWorkout,
            displayName: "Days Since Workout",
            unit: "days",
            source: .derived,
            normalisationBasis: "0 days = 1.0, 28+ days = 0.0, linear",
            scientificReference: "Mujika & Padilla 2000 — detraining timelines"
        ),
        SignalMeta(
            id: .acwr,
            displayName: "ACWR",
            unit: "ratio",
            source: .derived,
            normalisationBasis: "Tent function; optimal 0.8–1.1",
            scientificReference: "Gabbett 2016 — ACWR and injury risk"
        ),
    ]
}
```

- [ ] **Step 3.2: Build — expect no errors**

- [ ] **Step 3.3: Commit**

```bash
git add JournalInsight/Assessment/SignalRegistry.swift
git commit -m "feat(sp3a): add SignalRegistry with metadata + scientific references for all 12 signals"
```

---

## Task 4: SignalIngester

**Files:**
- Create: `JournalInsight/Assessment/SignalIngester.swift`
- Create: `JournalInsightTests/SignalIngesterTests.swift`

- [ ] **Step 4.1: Write tests for pure ingester logic (no HK store)**

```swift
// JournalInsightTests/SignalIngesterTests.swift
import Testing
import Foundation

@Suite("SignalIngesterTests")
struct SignalIngesterTests {

    @Test("Confidence is high when data is fresh (< 24h)")
    func highConfidenceFresh() {
        let ts = Date(timeIntervalSinceNow: -3600)  // 1 hour ago
        let conf = SignalIngester.confidence(timestamp: ts, sampleCount: 3)
        #expect(conf == .high)
    }

    @Test("Confidence is medium when data is 24–48h old")
    func mediumConfidence() {
        let ts = Date(timeIntervalSinceNow: -36 * 3600)  // 36h ago
        let conf = SignalIngester.confidence(timestamp: ts, sampleCount: 3)
        #expect(conf == .medium)
    }

    @Test("Confidence is low when data is 48–72h old")
    func lowConfidence() {
        let ts = Date(timeIntervalSinceNow: -60 * 3600)  // 60h ago
        let conf = SignalIngester.confidence(timestamp: ts, sampleCount: 3)
        #expect(conf == .low)
    }

    @Test("Confidence is unavailable when timestamp is distant past")
    func unavailableConfidence() {
        let ts = Date.distantPast
        let conf = SignalIngester.confidence(timestamp: ts, sampleCount: 0)
        #expect(conf == .unavailable)
    }

    @Test("ACWR computed correctly from workout entries")
    func acwrComputation() {
        // 7 workouts in last 7 days, 7 workouts in days 8–28 (28 day window, 7d:28d ratio)
        let cal = Calendar.current
        var entries: [WorkoutEntry] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: -i, to: .now)!
            entries.append(WorkoutEntry(date: d, source: .manual, durationSec: 3600))
        }
        for i in 7..<14 {
            let d = cal.date(byAdding: .day, value: -i, to: .now)!
            entries.append(WorkoutEntry(date: d, source: .manual, durationSec: 3600))
        }
        let acwr = SignalIngester.computeACWR(from: entries)
        // 7d: 7 sessions, 28d: 14 sessions. Chronic = 14/4 = 3.5/week. Acute = 7. ACWR = 7/3.5 = 2.0
        #expect(acwr != nil)
    }

    @Test("daysSinceLastWorkout returns 0 when trained today")
    func daysSinceToday() {
        let entry = WorkoutEntry(date: .now, source: .manual, durationSec: 3600)
        let days = SignalIngester.daysSinceLastWorkout(from: [entry])
        #expect(days == 0)
    }

    @Test("daysSinceLastWorkout returns nil when no entries")
    func daysSinceEmpty() {
        #expect(SignalIngester.daysSinceLastWorkout(from: []) == nil)
    }
}
```

- [ ] **Step 4.2: Run — expect compile error**

- [ ] **Step 4.3: Create SignalIngester.swift**

```swift
// JournalInsight/Assessment/SignalIngester.swift
import Foundation
import HealthKit

// 30-day baseline cache — recomputed weekly, stored in UserDefaults
private struct BaselineCache: Codable {
    var hrvMean: Double?
    var hrvSD: Double?
    var rhrMean: Double?
    var rhrSD: Double?
    var computedAt: Date = .distantPast
}

actor SignalIngester {
    private let store: HKHealthStore
    private let reader: HealthKitReader

    init(store: HKHealthStore = .init()) {
        self.store = store
        self.reader = HealthKitReader(store: store)
    }

    // MARK: — Public entry point

    /// Produces the full signal array from all available sources.
    /// `entries` is the full WorkoutEntry history (pass all from SwiftData).
    func ingest(workoutEntries: [WorkoutEntry]) async -> [Signal] {
        let baseline = await loadOrComputeBaseline()
        let recovery = await reader.latestRecovery()
        let nutrition = await readNutrition()

        var signals: [Signal] = []

        // HRV
        if let hrv = await latestQuantity(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms")),
           let mean = baseline.hrvMean, let sd = baseline.hrvSD {
            let norm = SignalNormaliser.normaliseHRV(current: hrv.value, baselineMean: mean, baselineSD: sd)
            signals.append(Signal(id: .hrv, normalisedValue: norm, rawValue: hrv.value,
                                  unit: "ms", timestamp: hrv.timestamp,
                                  confidence: Self.confidence(timestamp: hrv.timestamp, sampleCount: 1),
                                  source: .healthKit))
        }

        // Resting HR
        if let rhr = recovery.restingHR,
           let mean = baseline.rhrMean, let sd = baseline.rhrSD {
            let norm = SignalNormaliser.normaliseRestingHR(current: rhr, baselineMean: mean, baselineSD: sd)
            let ts = recovery.lastUpdated ?? .distantPast
            signals.append(Signal(id: .restingHR, normalisedValue: norm, rawValue: rhr,
                                  unit: "bpm", timestamp: ts,
                                  confidence: Self.confidence(timestamp: ts, sampleCount: 1),
                                  source: .healthKit))
        }

        // Sleep duration
        if let dur = recovery.sleepDurationSec {
            let norm = SignalNormaliser.normaliseSleepDuration(seconds: dur)
            let ts = recovery.lastUpdated ?? .distantPast
            signals.append(Signal(id: .sleepDuration, normalisedValue: norm, rawValue: dur / 3600,
                                  unit: "hours", timestamp: ts,
                                  confidence: Self.confidence(timestamp: ts, sampleCount: 1),
                                  source: .healthKit))
        }

        // Deep sleep ratio
        if let dur = recovery.sleepDurationSec, let deep = recovery.deepSleepSec, dur > 0 {
            let ratio = deep / dur
            let norm = SignalNormaliser.normaliseDeepSleepRatio(ratio: ratio)
            let ts = recovery.lastUpdated ?? .distantPast
            signals.append(Signal(id: .deepSleepRatio, normalisedValue: norm, rawValue: ratio,
                                  unit: "%", timestamp: ts,
                                  confidence: Self.confidence(timestamp: ts, sampleCount: 1),
                                  source: .healthKit))
        }

        // Caloric intake 7d
        if let ratio = nutrition.caloricRatio7d {
            let norm = SignalNormaliser.normaliseCaloricRatio(ratio: ratio)
            signals.append(Signal(id: .caloricIntake7d, normalisedValue: norm, rawValue: ratio,
                                  unit: "% goal", timestamp: .now,
                                  confidence: nutrition.trackingDays >= 4 ? .high : .medium,
                                  source: .healthKit))
        }

        // Protein 7d
        if let pPerKg = nutrition.proteinPerKg7d {
            let norm = SignalNormaliser.normaliseProteinPerKg(gPerKg: pPerKg)
            signals.append(Signal(id: .proteinIntake7d, normalisedValue: norm, rawValue: pPerKg,
                                  unit: "g/kg", timestamp: .now,
                                  confidence: nutrition.trackingDays >= 4 ? .high : .medium,
                                  source: .healthKit))
        }

        // ACWR from WorkoutEntry
        if let acwr = Self.computeACWR(from: workoutEntries) {
            let norm = SignalNormaliser.normaliseACWR(acwr: acwr)
            signals.append(Signal(id: .acwr, normalisedValue: norm, rawValue: acwr,
                                  unit: "ratio", timestamp: .now, confidence: .high, source: .derived))
        }

        // Days since last workout
        if let days = Self.daysSinceLastWorkout(from: workoutEntries) {
            let norm = SignalNormaliser.normaliseDaysSinceWorkout(days: days)
            signals.append(Signal(id: .daysSinceLastWorkout, normalisedValue: norm,
                                  rawValue: Double(days), unit: "days",
                                  timestamp: .now, confidence: .high, source: .derived))
        }

        return signals
    }

    // MARK: — Static helpers (testable without actor)

    static func confidence(timestamp: Date, sampleCount: Int) -> Confidence {
        let age = Date.now.timeIntervalSince(timestamp)
        guard age < 7 * 24 * 3600 else { return .unavailable }
        if age < 24 * 3600 && sampleCount >= 1 { return .high }
        if age < 48 * 3600 { return .medium }
        return .low
    }

    static func computeACWR(from entries: [WorkoutEntry]) -> Double? {
        let cal = Calendar.current
        let now = Date.now
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let twentyEightDaysAgo = cal.date(byAdding: .day, value: -28, to: now)!
        let acute = Double(entries.filter { $0.date >= sevenDaysAgo }.count)
        let chronic = Double(entries.filter { $0.date >= twentyEightDaysAgo }.count)
        guard chronic > 0 else { return nil }
        // Chronic is normalised per week: chronic sessions / 4 weeks
        let chronicPerWeek = chronic / 4.0
        return acute / chronicPerWeek
    }

    static func daysSinceLastWorkout(from entries: [WorkoutEntry]) -> Int? {
        guard let last = entries.max(by: { $0.date < $1.date }) else { return nil }
        return Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
    }

    // MARK: — Baseline computation (30-day stats for HRV + RHR)

    private func loadOrComputeBaseline() async -> BaselineCache {
        if let cached = loadBaselineCache(),
           Date.now.timeIntervalSince(cached.computedAt) < 7 * 24 * 3600 {
            return cached
        }
        var cache = BaselineCache()
        let (hrvMean, hrvSD) = await compute30DayStats(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms"))
        let (rhrMean, rhrSD) = await compute30DayStats(.restingHeartRate, unit: HKUnit(from: "count/min"))
        cache.hrvMean = hrvMean; cache.hrvSD = hrvSD
        cache.rhrMean = rhrMean; cache.rhrSD = rhrSD
        cache.computedAt = .now
        saveBaselineCache(cache)
        return cache
    }

    private func compute30DayStats(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> (mean: Double?, sd: Double?) {
        let qtype = HKQuantityType(type)
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: qtype,
                predicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let vals = (samples ?? []).compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
                guard vals.count >= 3 else { continuation.resume(returning: (nil, nil)); return }
                let mean = vals.reduce(0, +) / Double(vals.count)
                let sd = sqrt(vals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vals.count))
                continuation.resume(returning: (mean, max(sd, 1.0)))  // min SD = 1 to avoid div/0
            }
            store.execute(query)
        }
    }

    // MARK: — Nutrition reading

    private struct NutritionSnapshot {
        var caloricRatio7d: Double?  // consumed / goal (goal from HealthTraining config)
        var proteinPerKg7d: Double?  // g/kg bodyweight
        var trackingDays: Int = 0
    }

    private func readNutrition() async -> NutritionSnapshot {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        async let kcalData = sumQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), since: start)
        async let proteinData = sumQuantity(.dietaryProtein, unit: .gram(), since: start)
        async let weightData = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))

        let (kcal7d, kcalDays) = await kcalData
        let (protein7d, _) = await proteinData
        let weight = await weightData

        var snap = NutritionSnapshot()
        snap.trackingDays = kcalDays

        // Caloric goal: assume 2000 kcal/day if no Garmin TDEE available (SP4 improves this)
        let kCalGoal7d = 2000.0 * 7
        if let k = kcal7d, k > 0 { snap.caloricRatio7d = k / kCalGoal7d }

        if let p = protein7d, let w = weight.value, w > 0 {
            snap.proteinPerKg7d = (p / 7.0) / w  // avg daily protein / weight
        }

        return snap
    }

    private func sumQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date?) async -> (sum: Double?, days: Int) {
        let qtype = HKQuantityType(type)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: qtype,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                options: .cumulativeSum,
                anchorDate: Calendar.current.startOfDay(for: .now),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else { continuation.resume(returning: (nil, 0)); return }
                var total = 0.0; var days = 0
                results.enumerateStatistics(from: start ?? .distantPast, to: .now) { stat, _ in
                    if let sum = stat.sumQuantity() { total += sum.doubleValue(for: unit); days += 1 }
                }
                continuation.resume(returning: (total > 0 ? total : nil, days))
            }
            store.execute(query)
        }
    }

    private func latestQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, timestamp: Date)? {
        let qtype = HKQuantityType(type)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: qtype,
                predicate: HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -7, to: .now), end: .now),
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: (s.quantity.doubleValue(for: unit), s.endDate))
            }
            store.execute(query)
        }
    }

    // MARK: — Baseline cache persistence

    private static let baselineCacheKey = "signalBaselineCache"

    private func loadBaselineCache() -> BaselineCache? {
        guard let data = UserDefaults.standard.data(forKey: Self.baselineCacheKey) else { return nil }
        return try? JSONDecoder().decode(BaselineCache.self, from: data)
    }

    private func saveBaselineCache(_ cache: BaselineCache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.baselineCacheKey)
        }
    }
}
```

- [ ] **Step 4.4: Run tests — expect pass**

- [ ] **Step 4.5: Commit**

```bash
git add JournalInsight/Assessment/SignalIngester.swift JournalInsightTests/SignalIngesterTests.swift
git commit -m "feat(sp3a): add SignalIngester — produces typed Signal array from HK + WorkoutEntry"
```

---

## SP3a complete

Run full test suite (`⌘U`). All normaliser and ingester tests must pass.

```bash
git log --oneline -6
```

Expected commits:
```
feat(sp3a): add SignalIngester — produces typed Signal array from HK + WorkoutEntry
feat(sp3a): add SignalRegistry with metadata + scientific references for all 12 signals
feat(sp3a): add SignalNormaliser — normalisation functions for all 12 signal types
feat(sp3a): add Signal model — SignalID, Confidence, SignalSource, TrendDirection
```
