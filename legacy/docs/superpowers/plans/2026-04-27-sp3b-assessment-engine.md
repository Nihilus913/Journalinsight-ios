# SP3b — Composite Assessment Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the HealthTraining gate logic (`evaluate_kpi_gates` + `_compute_derived_metrics`) from Python to Swift, extend it with the SP3a signal set, and surface a `TrainingAssessment` (REDUCE/MAINTAIN/PROGRESS/REST) in the Training screen.

**Architecture:** `DerivedMetrics` ports `_compute_derived_metrics` — pure function, fully testable. `KpiRule` is a SwiftData model that stores the rule table (mirrors `plan.kpi_target` in the HealthTraining DB). `AssessmentEngine` ports `evaluate_kpi_gates`, consuming `[Signal]` from SP3a + `DerivedMetrics`. `AssessmentView` renders the gate panel (REDUCE/MAINTAIN/PROGRESS/REST) with contributing signals and override option.

**Tech Stack:** SwiftData (KpiRule model), Swift concurrency, Apple Testing framework.

**Prerequisites:** SP3a complete (Signal types, SignalIngester), SP2 (HealthKitReader), SP1 (WorkoutEntry).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Assessment/DerivedMetrics.swift` | Port of `_compute_derived_metrics` — pure computed struct |
| Create | `JournalInsight/Assessment/KpiRule.swift` | SwiftData model for rule table (mirrors plan.kpi_target) |
| Create | `JournalInsight/Assessment/AssessmentEngine.swift` | Port of `evaluate_kpi_gates`; returns TrainingAssessment |
| Create | `JournalInsight/Assessment/AssessmentView.swift` | Gate panel: REDUCE/MAINTAIN/PROGRESS/REST UI |
| Modify | `JournalInsight/Training/TrainingDetailView.swift` | Add AssessmentView at the top |
| Modify | `JournalInsight/JournalInsightApp.swift` | Add KpiRule to ModelContainer + seed default rules |
| Create | `JournalInsightTests/DerivedMetricsTests.swift` | Tests porting Python unit tests |
| Create | `JournalInsightTests/AssessmentEngineTests.swift` | Tests for REDUCE/MAINTAIN/PROGRESS gate logic |

---

## Task 1: DerivedMetrics — port `_compute_derived_metrics`

**Files:**
- Create: `JournalInsight/Assessment/DerivedMetrics.swift`
- Create: `JournalInsightTests/DerivedMetricsTests.swift`

- [ ] **Step 1.1: Write failing tests**

```swift
// JournalInsightTests/DerivedMetricsTests.swift
import Testing
import Foundation

@Suite("DerivedMetricsTests")
struct DerivedMetricsTests {

    // Row dict builders matching HealthTraining's format
    private func row(kcal: Double = 1800, kcalGoal: Double = 2000, protein: Double = 120,
                     weight: Double = 80, acwr: Double? = nil) -> [String: Double?] {
        var d: [String: Double?] = [
            "kcal_consumed": kcal, "kcal_goal": kcalGoal,
            "protein_g": protein, "weight_kg": weight,
        ]
        d["acwr"] = acwr
        return d
    }

    @Test("avg_kcal_goal_ratio computed correctly")
    func avgKcalGoalRatio() {
        let rows = Array(repeating: row(kcal: 1800, kcalGoal: 2000), count: 7)
        let m = DerivedMetrics(from: rows)
        // ratio = avg(1800) / avg(2000) = 0.9
        #expect(abs((m.avgKcalGoalRatio ?? 0) - 0.9) < 0.01)
    }

    @Test("protein_per_kg computed correctly")
    func proteinPerKg() {
        let rows = Array(repeating: row(protein: 160, weight: 80), count: 7)
        let m = DerivedMetrics(from: rows)
        #expect(abs((m.proteinPerKg ?? 0) - 2.0) < 0.01)
    }

    @Test("avg_kcal_deficit computed correctly")
    func avgDeficit() {
        let rows = Array(repeating: row(kcal: 1800, kcalGoal: 2000), count: 7)
        let m = DerivedMetrics(from: rows)
        #expect(abs((m.avgKcalDeficit ?? 0) - 200) < 1)
    }

    @Test("est_weekly_weight_change_kg computed correctly")
    func weeklyWeightChange() {
        // deficit 200 * 7 / 7700 ≈ 0.18 kg/week
        let rows = Array(repeating: row(kcal: 1800, kcalGoal: 2000), count: 7)
        let m = DerivedMetrics(from: rows)
        #expect(abs((m.estWeeklyWeightChangeKg ?? 0) - 0.18) < 0.01)
    }

    @Test("Returns nil when no rows")
    func emptyRows() {
        let m = DerivedMetrics(from: [])
        #expect(m.avgKcal == nil)
        #expect(m.avgKcalGoalRatio == nil)
    }

    @Test("trend returns flat for fewer than 4 data points")
    func trendFewPoints() {
        let vals = [1800.0, 1900.0]
        #expect(DerivedMetrics.trend(vals) == .flat)
    }

    @Test("trend returns up when second half higher")
    func trendUp() {
        let vals = [1000.0, 1100.0, 1500.0, 1600.0]
        #expect(DerivedMetrics.trend(vals) == .up)
    }

    @Test("trend returns down when second half lower")
    func trendDown() {
        let vals = [1600.0, 1500.0, 1100.0, 1000.0]
        #expect(DerivedMetrics.trend(vals) == .down)
    }
}
```

- [ ] **Step 1.2: Run — expect compile error**

- [ ] **Step 1.3: Create DerivedMetrics.swift**

```swift
// JournalInsight/Assessment/DerivedMetrics.swift
import Foundation

// Port of HealthTraining app/planning/service.py:_compute_derived_metrics
// Pure value type — all inputs via init, no I/O.
struct DerivedMetrics {

    // MARK: — Constants (mirrors Python)
    static let progressKcalRatioMin: Double = 0.80
    static let progressKcalRatioMax: Double = 1.10
    static let progressProteinPerKg: Double = 2.0
    static let trackingKcalMin: Double = 1200
    static let trackingMealsMin: Int = 3
    static let minTrackedDays: Int = 4

    // MARK: — Derived values (nil when insufficient data)
    let avgKcal: Double?
    let avgProtein: Double?
    let avgSleepScore: Double?
    let avgWeight: Double?
    let avgRhr: Double?
    let avgSteps: Double?
    let avgBodyBattery: Double?
    let avgKcalBurned: Double?
    let avgKcalGoalRatio: Double?    // consumed / goal
    let proteinPerKg: Double?        // avg_protein / avg_weight
    let avgKcalDeficit: Double?      // goal - consumed (positive = deficit)
    let estWeeklyWeightChangeKg: Double?
    let trends: [String: TrendDirection]
    let acwr: Double?

    // MARK: — Init from raw daily row dicts
    // Keys match HealthTraining core.* table column names
    init(from rows: [[String: Double?]]) {
        guard !rows.isEmpty else {
            avgKcal = nil; avgProtein = nil; avgSleepScore = nil
            avgWeight = nil; avgRhr = nil; avgSteps = nil
            avgBodyBattery = nil; avgKcalBurned = nil
            avgKcalGoalRatio = nil; proteinPerKg = nil
            avgKcalDeficit = nil; estWeeklyWeightChangeKg = nil
            trends = [:]; acwr = nil
            return
        }

        func vals(_ key: String) -> [Double] {
            rows.compactMap { $0[key] ?? nil }
        }

        let kcalVals   = vals("kcal_consumed")
        let proteinVals = vals("protein_g")
        let sleepVals  = vals("sleep_score")
        let weightVals = vals("weight_kg")
        let rhrVals    = vals("rhr_bpm")
        let stepsVals  = vals("steps")
        let bbVals     = vals("body_battery_avg")
        let burnedVals = vals("kcal_burned_active")
        let goalVals   = vals("kcal_goal")
        let acwrVals   = vals("acwr")

        let avgKcalLocal   = Self.avg(kcalVals)
        let avgGoalLocal   = Self.avg(goalVals)
        let avgWeightLocal = Self.avg(weightVals)
        let avgProtLocal   = Self.avg(proteinVals)

        avgKcal         = avgKcalLocal
        avgProtein      = avgProtLocal
        avgSleepScore   = Self.avg(sleepVals)
        avgWeight       = avgWeightLocal
        avgRhr          = Self.avg(rhrVals)
        avgSteps        = Self.avg(stepsVals)
        avgBodyBattery  = Self.avg(bbVals)
        avgKcalBurned   = Self.avg(burnedVals)
        acwr            = acwrVals.last   // latest ACWR is the current value

        if let k = avgKcalLocal, let g = avgGoalLocal, g != 0 {
            avgKcalGoalRatio = (k / g).rounded(toPlaces: 3)
        } else { avgKcalGoalRatio = nil }

        if let p = avgProtLocal, let w = avgWeightLocal, w != 0 {
            proteinPerKg = (p / w).rounded(toPlaces: 2)
        } else { proteinPerKg = nil }

        if let k = avgKcalLocal, let g = avgGoalLocal {
            avgKcalDeficit = (g - k).rounded(toPlaces: 1)
        } else { avgKcalDeficit = nil }

        if let d = avgKcalDeficit {
            estWeeklyWeightChangeKg = (d * 7 / 7700).rounded(toPlaces: 2)
        } else { estWeeklyWeightChangeKg = nil }

        trends = [
            "kcal":         Self.trend(kcalVals).rawValue,
            "protein":      Self.trend(proteinVals).rawValue,
            "rhr":          Self.trend(rhrVals).rawValue,
            "sleep":        Self.trend(sleepVals).rawValue,
            "acwr":         Self.trend(acwrVals).rawValue,
            "body_battery": Self.trend(bbVals).rawValue,
            "kcal_burned":  Self.trend(burnedVals).rawValue,
        ].mapValues { TrendDirection(rawValue: $0) ?? .flat }
    }

    // MARK: — Static helpers (testable)

    static func avg(_ vals: [Double]) -> Double? {
        guard !vals.isEmpty else { return nil }
        return (vals.reduce(0, +) / Double(vals.count)).rounded(toPlaces: 1)
    }

    /// Compare first half vs second half; return up/down/flat.
    /// Mirrors Python _trend() — 2% threshold.
    static func trend(_ vals: [Double]) -> TrendDirection {
        guard vals.count >= 4 else { return .flat }
        let mid = vals.count / 2
        let first = vals[..<mid].reduce(0, +) / Double(mid)
        let last = vals[mid...].reduce(0, +) / Double(vals.count - mid)
        guard first != 0 else { return .flat }
        let pct = (last - first) / abs(first)
        if pct > 0.02 { return .up }
        if pct < -0.02 { return .down }
        return .flat
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
```

- [ ] **Step 1.4: Run tests — expect pass**

- [ ] **Step 1.5: Commit**

```bash
git add JournalInsight/Assessment/DerivedMetrics.swift JournalInsightTests/DerivedMetricsTests.swift
git commit -m "feat(sp3b): add DerivedMetrics — port of Python _compute_derived_metrics"
```

---

## Task 2: KpiRule SwiftData model

**Files:**
- Create: `JournalInsight/Assessment/KpiRule.swift`

- [ ] **Step 2.1: Create the file**

```swift
// JournalInsight/Assessment/KpiRule.swift
import Foundation
import SwiftData

// Mirrors plan.kpi_target in HealthTraining PostgreSQL.
// Stored in SwiftData for offline use.
@Model
class KpiRule {
    var ruleId: Int       // ordering / priority
    var metric: String    // e.g. "avg_kcal_goal_ratio", "acwr", "proteinPerKg"
    var operator_: String // ">", "<", ">=", "<=", "between"
    var threshold: Double
    var thresholdHi: Double?
    var description_: String  // must contain "reduce", "maintain", or "progress" (case-insensitive)

    init(ruleId: Int, metric: String, operator_: String,
         threshold: Double, thresholdHi: Double? = nil, description_: String) {
        self.ruleId = ruleId
        self.metric = metric
        self.operator_ = operator_
        self.threshold = threshold
        self.thresholdHi = thresholdHi
        self.description_ = description_
    }
}

// Default rule set mirroring the HealthTraining database seed.
// Seeded on first launch if no rules exist.
enum KpiRuleDefaults {
    static let rules: [KpiRule] = [
        // REDUCE — ACWR overload
        KpiRule(ruleId: 1, metric: "acwr", operator_: ">", threshold: 1.3,
                description_: "Reduce load — ACWR overload risk"),
        // REDUCE — chronic underfueling
        KpiRule(ruleId: 2, metric: "avg_kcal_goal_ratio", operator_: "<", threshold: 0.6,
                description_: "Reduce intensity — severe underfueling detected"),
        // MAINTAIN — ACWR in sweet spot
        KpiRule(ruleId: 3, metric: "acwr", operator_: "between", threshold: 0.8, thresholdHi: 1.1,
                description_: "Maintain current load — ACWR optimal"),
        // PROGRESS — nutrition and ACWR both good
        KpiRule(ruleId: 4, metric: "avg_kcal_goal_ratio", operator_: "between",
                threshold: 0.8, thresholdHi: 1.1,
                description_: "Progress available — nutrition on target"),
    ]
}
```

- [ ] **Step 2.2: Add KpiRule to ModelContainer in JournalInsightApp.swift**

```swift
.modelContainer(for: [JournalEntry.self, Goal.self, Tag.self, WorkoutEntry.self, KpiRule.self])
```

- [ ] **Step 2.3: Seed default rules on first launch**

In `JournalInsightApp.swift`, add a seed helper. In the `.task` or model container result handler, after registering background tasks, add:

```swift
// Seed KPI rules on first launch
let ruleDescriptor = FetchDescriptor<KpiRule>()
if let count = try? context.fetchCount(ruleDescriptor), count == 0 {
    for rule in KpiRuleDefaults.rules {
        context.insert(rule)
    }
    try? context.save()
}
```

- [ ] **Step 2.4: Build — expect no errors**

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/Assessment/KpiRule.swift JournalInsight/JournalInsightApp.swift
git commit -m "feat(sp3b): add KpiRule SwiftData model + default rule seed"
```

---

## Task 3: AssessmentEngine — port `evaluate_kpi_gates`

**Files:**
- Create: `JournalInsight/Assessment/AssessmentEngine.swift`
- Create: `JournalInsightTests/AssessmentEngineTests.swift`

- [ ] **Step 3.1: Write failing tests**

```swift
// JournalInsightTests/AssessmentEngineTests.swift
import Testing
import Foundation

@Suite("AssessmentEngineTests")
struct AssessmentEngineTests {

    private func makeRules() -> [KpiRule] { KpiRuleDefaults.rules }

    private func makeMetrics(kcalRatio: Double = 0.9, acwr: Double = 1.0, proteinPerKg: Double = 2.0) -> DerivedMetrics {
        let rows: [[String: Double?]] = (0..<7).map { _ in [
            "kcal_consumed": kcalRatio * 2000,
            "kcal_goal": 2000,
            "protein_g": proteinPerKg * 80,
            "weight_kg": 80,
            "acwr": acwr,
        ] }
        return DerivedMetrics(from: rows)
    }

    @Test("REDUCE when ACWR > 1.3")
    func reduceHighACWR() {
        let result = AssessmentEngine.evaluate(
            metrics: makeMetrics(acwr: 1.4),
            rules: makeRules(),
            signals: []
        )
        #expect(result.recommendation == .reduce)
    }

    @Test("REDUCE when caloric ratio < 0.6")
    func reduceSevereUnderfueling() {
        let result = AssessmentEngine.evaluate(
            metrics: makeMetrics(kcalRatio: 0.5),
            rules: makeRules(),
            signals: []
        )
        #expect(result.recommendation == .reduce)
    }

    @Test("PROGRESS when nutrition on target + ACWR optimal + protein adequate")
    func progressGoodConditions() {
        let result = AssessmentEngine.evaluate(
            metrics: makeMetrics(kcalRatio: 0.95, acwr: 1.0, proteinPerKg: 2.1),
            rules: makeRules(),
            signals: []
        )
        #expect(result.recommendation == .progress)
    }

    @Test("MAINTAIN when ACWR in sweet spot but nutrition off")
    func maintainNutritionLow() {
        let result = AssessmentEngine.evaluate(
            metrics: makeMetrics(kcalRatio: 0.7, acwr: 0.9, proteinPerKg: 1.5),
            rules: makeRules(),
            signals: []
        )
        #expect(result.recommendation == .maintain)
    }

    @Test("Assessment always includes disclaimer")
    func alwaysHasDisclaimer() {
        let result = AssessmentEngine.evaluate(metrics: makeMetrics(), rules: makeRules(), signals: [])
        #expect(!result.disclaimer.isEmpty)
    }

    @Test("Triggered rules list non-empty when REDUCE fires")
    func triggeredRulesNonEmpty() {
        let result = AssessmentEngine.evaluate(
            metrics: makeMetrics(acwr: 1.5),
            rules: makeRules(),
            signals: []
        )
        #expect(!result.triggeredRules.isEmpty)
    }
}
```

- [ ] **Step 3.2: Run — expect compile error**

- [ ] **Step 3.3: Create AssessmentEngine.swift**

```swift
// JournalInsight/Assessment/AssessmentEngine.swift
import Foundation

enum Recommendation: String, Codable {
    case progress   // fueling good, recovery good, ACWR has headroom
    case maintain   // stable, proceed as planned
    case reduce     // chronic underfueling, poor recovery, or injury risk
    case rest       // strong negative signals across multiple dimensions
}

struct PlanAdjustment: Codable {
    let description: String
}

struct SignalContribution: Codable {
    let signalId: SignalID
    let displayName: String
    let normalisedValue: Double
    let confidence: Confidence
    let direction: String  // "positive", "negative", "neutral"
}

struct TrainingAssessment {
    let recommendation: Recommendation
    let triggeredRules: [String]
    let planAdjustments: [PlanAdjustment]
    let contributingSignals: [SignalContribution]
    let trends: [String: TrendDirection]
    let disclaimer: String
    let generatedAt: Date
}

enum AssessmentEngine {

    static let disclaimer = "Training guidance only — not medical advice. Always listen to your body and consult a healthcare professional for persistent symptoms."

    /// Evaluates KPI gate rules and returns a TrainingAssessment.
    /// Pure function — no I/O. Mirrors HealthTraining evaluate_kpi_gates().
    static func evaluate(
        metrics: DerivedMetrics,
        rules: [KpiRule],
        signals: [Signal]
    ) -> TrainingAssessment {
        var triggered: [String] = []

        let sortedRules = rules.sorted { $0.ruleId < $1.ruleId }

        for rule in sortedRules {
            let fired = evalRule(rule: rule, metrics: metrics)
            guard fired == true else { continue }

            let desc = rule.description_.lowercased()
            triggered.append("\(rule.metric) \(rule.operator_) \(rule.threshold) — \(rule.description_)")

            if desc.contains("reduce") {
                return TrainingAssessment(
                    recommendation: .reduce,
                    triggeredRules: triggered,
                    planAdjustments: reduceAdjustments(metrics: metrics),
                    contributingSignals: buildContributions(signals: signals),
                    trends: metrics.trends,
                    disclaimer: disclaimer,
                    generatedAt: .now
                )
            }

            if desc.contains("maintain") {
                // Check if we can progress instead
                if canProgress(metrics: metrics) {
                    return TrainingAssessment(
                        recommendation: .progress,
                        triggeredRules: [],
                        planAdjustments: progressAdjustments(metrics: metrics),
                        contributingSignals: buildContributions(signals: signals),
                        trends: metrics.trends,
                        disclaimer: disclaimer,
                        generatedAt: .now
                    )
                }
                return TrainingAssessment(
                    recommendation: .maintain,
                    triggeredRules: triggered,
                    planAdjustments: [],
                    contributingSignals: buildContributions(signals: signals),
                    trends: metrics.trends,
                    disclaimer: disclaimer,
                    generatedAt: .now
                )
            }

            if desc.contains("progress"), canProgress(metrics: metrics) {
                return TrainingAssessment(
                    recommendation: .progress,
                    triggeredRules: [],
                    planAdjustments: progressAdjustments(metrics: metrics),
                    contributingSignals: buildContributions(signals: signals),
                    trends: metrics.trends,
                    disclaimer: disclaimer,
                    generatedAt: .now
                )
            }
        }

        // Default: MAINTAIN
        return TrainingAssessment(
            recommendation: .maintain,
            triggeredRules: [],
            planAdjustments: [],
            contributingSignals: buildContributions(signals: signals),
            trends: metrics.trends,
            disclaimer: disclaimer,
            generatedAt: .now
        )
    }

    // MARK: — Private

    private static func evalRule(rule: KpiRule, metrics: DerivedMetrics) -> Bool? {
        let val: Double?
        switch rule.metric {
        case "acwr":                val = metrics.acwr
        case "avg_kcal_goal_ratio": val = metrics.avgKcalGoalRatio
        case "proteinPerKg":        val = metrics.proteinPerKg
        case "avgKcal":             val = metrics.avgKcal
        default:                    return nil
        }
        guard let v = val else { return nil }
        switch rule.operator_ {
        case ">":       return v > rule.threshold
        case "<":       return v < rule.threshold
        case ">=":      return v >= rule.threshold
        case "<=":      return v <= rule.threshold
        case "between":
            let hi = rule.thresholdHi ?? rule.threshold
            return v >= rule.threshold && v <= hi
        default: return nil
        }
    }

    private static func canProgress(metrics: DerivedMetrics) -> Bool {
        let ratioOk = metrics.avgKcalGoalRatio.map {
            $0 >= DerivedMetrics.progressKcalRatioMin && $0 <= DerivedMetrics.progressKcalRatioMax
        } ?? false
        let proteinOk = metrics.proteinPerKg.map { $0 >= DerivedMetrics.progressProteinPerKg } ?? false
        return ratioOk && proteinOk
    }

    private static func reduceAdjustments(metrics: DerivedMetrics) -> [PlanAdjustment] {
        var adj: [PlanAdjustment] = [PlanAdjustment(description: "Reduce sets by 1 this session")]
        if let acwr = metrics.acwr, acwr > 1.3 {
            adj.append(PlanAdjustment(description: "ACWR \(String(format: "%.2f", acwr)) — consider an extra rest day"))
        }
        return adj
    }

    private static func progressAdjustments(metrics: DerivedMetrics) -> [PlanAdjustment] {
        var adj: [PlanAdjustment] = []
        if let acwr = metrics.acwr, acwr < 1.1 {
            adj.append(PlanAdjustment(description: "ACWR \(String(format: "%.2f", acwr)) has headroom — consider increasing load"))
        }
        adj.append(PlanAdjustment(description: "Consider adding 2.5 kg to primary compound lifts"))
        return adj
    }

    private static func buildContributions(signals: [Signal]) -> [SignalContribution] {
        signals.map { s in
            let meta = SignalRegistry.all[s.id]
            let dir: String
            if s.value >= 0.7 { dir = "positive" }
            else if s.value <= 0.3 { dir = "negative" }
            else { dir = "neutral" }
            return SignalContribution(
                signalId: s.id,
                displayName: meta?.displayName ?? s.id.rawValue,
                normalisedValue: s.value,
                confidence: s.confidence,
                direction: dir
            )
        }
    }
}
```

- [ ] **Step 3.4: Run tests — expect pass**

- [ ] **Step 3.5: Commit**

```bash
git add JournalInsight/Assessment/AssessmentEngine.swift JournalInsightTests/AssessmentEngineTests.swift
git commit -m "feat(sp3b): add AssessmentEngine — port of HealthTraining evaluate_kpi_gates"
```

---

## Task 4: AssessmentView — gate panel UI

**Files:**
- Create: `JournalInsight/Assessment/AssessmentView.swift`

- [ ] **Step 4.1: Create the file**

```swift
// JournalInsight/Assessment/AssessmentView.swift
import SwiftUI
import SwiftData

struct AssessmentView: View {
    let assessment: TrainingAssessment
    @State private var showDetails = false
    @State private var overrideChoice: Recommendation? = nil

    private var displayRec: Recommendation { overrideChoice ?? assessment.recommendation }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                recommendationChip
                Spacer()
                Button(showDetails ? "Less" : "Details") {
                    withAnimation { showDetails.toggle() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if showDetails {
                Divider()
                detailSection
            }
        }
        .padding()
        .background(backgroundColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(backgroundColor.opacity(0.3), lineWidth: 1))
    }

    // MARK: — Subviews

    private var recommendationChip: some View {
        HStack(spacing: 6) {
            Image(systemName: displayRec.icon)
            Text(displayRec.label)
                .font(.headline)
        }
        .foregroundStyle(backgroundColor)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Plan adjustments
            if !assessment.planAdjustments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(assessment.planAdjustments, id: \.description) { adj in
                        Label(adj.description, systemImage: "lightbulb")
                            .font(.caption)
                    }
                }
            }

            // Triggered rules
            if !assessment.triggeredRules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Triggered rules").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(assessment.triggeredRules, id: \.self) { rule in
                        Text("• " + rule).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // Contributing signals (top 4)
            if !assessment.contributingSignals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signals").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(assessment.contributingSignals.prefix(4), id: \.signalId) { sig in
                        HStack {
                            Circle()
                                .fill(signalColor(sig.direction))
                                .frame(width: 8, height: 8)
                            Text(sig.displayName)
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", sig.normalisedValue * 100))
                                .font(.caption2).foregroundStyle(.secondary)
                            confidenceBadge(sig.confidence)
                        }
                    }
                }
            }

            // Override option
            HStack(spacing: 8) {
                Text("Override:").font(.caption).foregroundStyle(.secondary)
                ForEach([Recommendation.reduce, .maintain, .progress], id: \.self) { r in
                    Button(r.label) { overrideChoice = overrideChoice == r ? nil : r }
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(overrideChoice == r ? r.color.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundStyle(overrideChoice == r ? r.color : .secondary)
                        .clipShape(Capsule())
                }
            }

            // Disclaimer
            Text(assessment.disclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: — Helpers

    private var backgroundColor: Color { displayRec.color }

    private var rationale: String {
        switch displayRec {
        case .progress: return "Fuelling on target and load has headroom — consider increasing."
        case .maintain: return "Conditions stable. Proceed with planned session."
        case .reduce:   return "Recovery or fuelling signals suggest reducing intensity today."
        case .rest:     return "Multiple negative signals — active recovery recommended."
        }
    }

    private func signalColor(_ direction: String) -> Color {
        switch direction {
        case "positive": return .green
        case "negative": return .red
        default:         return .gray
        }
    }

    private func confidenceBadge(_ c: Confidence) -> some View {
        Text(c == .unavailable ? "–" : c == .high ? "●●●" : c == .medium ? "●●" : "●")
            .font(.caption2)
            .foregroundStyle(c == .high ? .green : c == .medium ? .yellow : .red)
    }
}

extension Recommendation {
    var label: String {
        switch self {
        case .progress: return "PROGRESS"
        case .maintain: return "MAINTAIN"
        case .reduce:   return "REDUCE"
        case .rest:     return "REST"
        }
    }

    var icon: String {
        switch self {
        case .progress: return "arrow.up.circle.fill"
        case .maintain: return "arrow.right.circle.fill"
        case .reduce:   return "arrow.down.circle.fill"
        case .rest:     return "bed.double.fill"
        }
    }

    var color: Color {
        switch self {
        case .progress: return .green
        case .maintain: return .orange
        case .reduce:   return .red
        case .rest:     return .indigo
        }
    }
}

#Preview {
    AssessmentView(assessment: TrainingAssessment(
        recommendation: .progress,
        triggeredRules: [],
        planAdjustments: [PlanAdjustment(description: "Consider adding 2.5 kg to bench press")],
        contributingSignals: [],
        trends: [:],
        disclaimer: AssessmentEngine.disclaimer,
        generatedAt: .now
    ))
    .padding()
}
```

- [ ] **Step 4.2: Build — expect no errors**

- [ ] **Step 4.3: Commit**

```bash
git add JournalInsight/Assessment/AssessmentView.swift
git commit -m "feat(sp3b): add AssessmentView gate panel with REDUCE/MAINTAIN/PROGRESS/REST + override"
```

---

## Task 5: Wire AssessmentEngine into TrainingDetailView

**Files:**
- Modify: `JournalInsight/Training/TrainingDetailView.swift`

- [ ] **Step 5.1: Add assessment state and loading logic**

In `TrainingDetailView`, add:

```swift
@Query private var kpiRules: [KpiRule]
@State private var assessment: TrainingAssessment? = nil
```

Add a `.task` modifier to the ScrollView:

```swift
.task {
    await loadAssessment()
}
```

Add the private method:

```swift
private func loadAssessment() async {
    let metrics = DerivedMetrics(from: [])  // SP4 will populate real rows; empty in SP3
    let ingester = SignalIngester()
    let signals = await ingester.ingest(workoutEntries: Array(entries))
    let result = AssessmentEngine.evaluate(metrics: metrics, rules: kpiRules, signals: signals)
    await MainActor.run { assessment = result }
}
```

- [ ] **Step 5.2: Add AssessmentView at the top of the ScrollView content**

Inside the `VStack(alignment: .leading, spacing: 20)`, add as the first item:

```swift
if let a = assessment {
    AssessmentView(assessment: a)
}
```

- [ ] **Step 5.3: Build and run — verify gate panel appears at top of Training screen**

The panel will show MAINTAIN (no real daily metrics yet — those come in SP4). Verify it renders without crashing.

- [ ] **Step 5.4: Commit**

```bash
git add JournalInsight/Training/TrainingDetailView.swift
git commit -m "feat(sp3b): wire AssessmentEngine into TrainingDetailView"
```

---

## SP3b complete

Run full test suite (`⌘U`). All derived metrics and assessment engine tests must pass.

```bash
git log --oneline -8
```

Expected commits:
```
feat(sp3b): wire AssessmentEngine into TrainingDetailView
feat(sp3b): add AssessmentView gate panel with REDUCE/MAINTAIN/PROGRESS/REST + override
feat(sp3b): add AssessmentEngine — port of HealthTraining evaluate_kpi_gates
feat(sp3b): add KpiRule SwiftData model + default rule seed
feat(sp3b): add DerivedMetrics — port of Python _compute_derived_metrics
```
