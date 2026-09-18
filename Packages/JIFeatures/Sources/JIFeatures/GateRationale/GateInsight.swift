import Foundation
import JICore

/// The slice of the oracle `mobile/src/lib/insight.ts` this screen needs: `actionForTriggeredRules`
/// and its parser. (`buildInsight`, the Today hero's one-sentence line, is Today's, not this lane's
/// — it is not ported here and must not be re-derived separately when it lands.)
nonisolated enum GateInsight {
    /// Metric name (as it appears at the head of a `triggeredRules` entry) -> a concrete, imperative
    /// next step. Read by `actionForTriggeredRules` for ANY recommendation whose rules fired with no
    /// `suggestions[]` — HT's `app/planning/service.py` returns `suggestions=[]` for its MAINTAIN
    /// branch too (e.g. acwr's undertraining rule), so acwr's copy stays direction-agnostic rather
    /// than assuming the REDUCE ("too high") direction.
    static let actionByMetric: [String: String] = [
        "avg_protein_7d": "front-load protein earlier in the day and hit target most days this week",
        "avg_kcal_7d": "bring kcal back up toward goal — this is chronic under-fueling, not a plateau",
        "sleep_score_7d": "protect sleep tonight before anything else",
        "acwr": "bring training load back toward the target range this week",
    ]
    static let defaultAction = "ease off and let the trend recover before pushing again"

    /// Pull the metric name off the front of a `triggeredRules` entry and the human-readable reason
    /// out of its trailing `"(REDUCE: insufficient protein)"` parenthetical.
    ///
    /// Ported verbatim INCLUDING the oracle's non-greedy `[^)]*`, which does not match a description
    /// carrying its own nested parenthetical ("… (REDUCE: chronic underfueling (5+ of 7 days))") and
    /// so returns `reason == nil` for those — a documented gap (see `GateHumanizeRule`'s header).
    /// `actionForTriggeredRules` only reads `metric`, so the gap does not reach this screen's copy;
    /// it is kept rather than fixed so the Swift and RN actions cannot diverge.
    static func parseTriggeredRule(_ rule: String) -> (metric: String, reason: String?) {
        let metric = rule.firstMatch(of: /^(\S+)/).map { String($0.1) } ?? ""
        let verdictPrefix = /^(REDUCE|MAINTAIN|PROGRESS):\s*/.ignoresCase()
        let reason = rule.firstMatch(of: /\(([^)]*)\)\s*$/)
            .map { String($0.1).replacing(verdictPrefix, with: "").trimmingCharacters(in: .whitespaces) }
        return (metric, reason)
    }

    /// The "what should I actually do" action Today's insight line derives for a REDUCE day, reused
    /// here as the Suggestions section's content whenever a rule fired but the gate handed back no
    /// `suggestions[]` — never invented separately. Prefers a real suggestion when the gate supplied
    /// one, else derives the action from what actually triggered.
    static func actionForTriggeredRules(_ gate: GateResponse) -> String {
        if let suggestion = gate.suggestions.first { return suggestion }
        if let rule = gate.triggeredRules.first,
           let action = actionByMetric[parseTriggeredRule(rule).metric] { return action }
        return defaultAction
    }

    /// Pure: "1 of 8 days tracked · needs 4" from the gate response's own counts.
    static func trackedDaysLine(_ gate: GateResponse) -> String {
        "\(gate.trackedDays) of \(gate.totalDays) days tracked · needs \(gate.minTrackedDays)"
    }

    /// Oracle `RECOMMENDATION_LABEL`. The 2026-09-08 fix: this is the WEEKLY NUTRITION KPI gate's
    /// verdict, not the morning readiness verdict — it lives in its own card, never under the
    /// verdict word.
    static func recommendationLabel(_ recommendation: GateRecommendation) -> String {
        switch recommendation {
        case .progress: "Gate recommends PROGRESS"
        case .maintain: "Gate recommends MAINTAIN"
        case .reduce: "Gate recommends REDUCE"
        case .insufficientData: "Not enough tracked days yet for a recommendation"
        }
    }
}
