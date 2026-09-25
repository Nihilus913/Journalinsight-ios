import Foundation
import JICore
import JICompute

/// B-42 (W-B46 L2) — the Today insight line, ported 1:1 from the RN oracle
/// `mobile/src/lib/insight.ts` (`buildInsight`), with its jest suite ported to Swift Testing
/// (`InsightSentenceTests`). ONE sentence built from data Today already fetched for the hero
/// (`gate` + `morning`): no extra round-trip, no model call. Bevel's narrative card, filled from
/// our own structured gate reasoning.
///
/// Priority order (today's training call first, then the week's single biggest lever):
///   1. morning verdict auto-regulated     -> the hub's trimmed prescription (W-FIX1 BUG-03)
///   2. morning verdict REDUCED            -> today's session was capped
///   3. morning verdict MODIFIED           -> today's session was swapped
///   4. `gate.recommendation == .reduce`   -> "<session>. This week: <action>." — the WEEKLY
///      nutrition gate as its own sentence, never glued onto the training word (W-FIX1 BUG-27)
///   5. glycogen / carb-watch floor breach -> `carbs3dAvg` vs `carbWatchFloor`
///   6. `gate.recommendation == .progress` -> the gate's own suggestion (the lever)
///   7. protein gap vs the 2 g/kg goal     -> `gate.averages`
///   8. weight trend                       -> `gate.averages`
///   9. fallback: summarises the verdict itself (never empty)
///
/// E15-5 (oracle): whenever a REDUCE/REDUCED/MODIFIED branch fires, the sentence carries one
/// concrete, imperative action — never just a warning. W-FIX1 BUG-27: no raw hub word (GO,
/// REDUCE, REDUCED, MODIFIED, PROGRESS) is ever part of the sentence; the hero leads it with the
/// user word (Full / Modified / Rest).
public nonisolated enum InsightSentence {
    /// The one-sentence Today insight. Never empty.
    public static func build(gate: GateResponse?, morning: MorningResponse?) -> String {
        guard let gate, let morning else { return noVerdictCopy }

        let v = verdictParts(morning.verdict)
        if isAutoRegulated(v) { return autoRegulatedMorning(v) }
        if let verdict = morning.verdict {
            if verdict.hasPrefix("REDUCED") { return reducedMorning(session: v.session) }
            if verdict.hasPrefix("MODIFIED") { return modifiedMorning(session: v.session) }
        }
        if gate.recommendation == .reduce {
            let weekly = gateReduce(gate)
            return v.session.isEmpty ? weekly : "\(v.session). \(weekly)"
        }

        if let carbWatch = carbWatch(carbs3dAvg: morning.carbs3dAvg, floor: morning.carbWatchFloor) { return carbWatch }

        if gate.recommendation == .progress, let first = gate.suggestions.first {
            return "On track to progress — \(lowerFirst(first))."
        }

        if let protein = proteinGap(avgProtein7d: gate.averages.avgProtein7d, avgWeightKg: gate.averages.avgWeightKg) { return protein }
        if let weight = weightTrend(estWeeklyWeightChangeKg: gate.averages.estWeeklyWeightChangeKg) { return weight }
        return fallback(morning)
    }

    // MARK: - Safety / cap tier

    /// Metric name (as it heads a `triggered_rules` entry, e.g. `"avg_protein_7d 118.0 vs
    /// threshold 130.0 (REDUCE: insufficient protein)"`) -> a concrete, imperative next step.
    /// `acwr`'s copy stays direction-agnostic: `actionForTriggeredRules` is read for any
    /// recommendation whose rules fired with no `suggestions[]` (HT `app/planning/service.py`
    /// returns `suggestions=[]` for its MAINTAIN branch too).
    static let actionByMetric: [String: String] = [
        "avg_protein_7d": "front-load protein earlier in the day and hit target most days this week",
        "avg_kcal_7d": "bring kcal back up toward goal — this is chronic under-fueling, not a plateau",
        "sleep_score_7d": "protect sleep tonight before anything else",
        "acwr": "bring training load back toward the target range this week",
    ]
    static let defaultAction = "ease off and let the trend recover before pushing again"

    /// Pulls the metric name off the front of a `triggered_rules` entry and the human reason out
    /// of its trailing `"(REDUCE: insufficient protein)"` parenthetical — mirrors the string HT
    /// `app/planning/service.py` builds.
    static func parseTriggeredRule(_ rule: String) -> (metric: String, reason: String?) {
        let metric = String(rule.split(separator: " ", maxSplits: 1).first ?? "")
        var reason: String?
        if let match = rule.firstMatch(of: /\(([^)]*)\)\s*$/) {
            let inner = String(match.1)
            let stripped = inner.replacing(/^(?i)(REDUCE|MAINTAIN|PROGRESS):\s*/, with: "")
            reason = stripped.trimmingCharacters(in: .whitespaces)
        }
        return (metric, reason)
    }

    /// Oracle `actionForTriggeredRules` — prefer a real gate suggestion, else derive the action
    /// from whatever actually triggered, else the neutral default. Also read by the gate-rationale
    /// screen's Suggestions fallback in the oracle (kept public for that reuse).
    public static func actionForTriggeredRules(_ gate: GateResponse) -> String {
        let parsed = gate.triggeredRules.first.map(parseTriggeredRule)
        return gate.suggestions.first ?? parsed.flatMap { actionByMetric[$0.metric] } ?? defaultAction
    }

    /// The weekly nutrition gate's REDUCE as one plain sentence: "This week (<reason>): <action>."
    static func gateReduce(_ gate: GateResponse) -> String {
        let parsed = gate.triggeredRules.first.map(parseTriggeredRule)
        let action = actionForTriggeredRules(gate)
        if let reason = parsed?.reason, !reason.isEmpty {
            return "This week (\(reason)): \(lowerFirst(action))."
        }
        return "This week: \(lowerFirst(action))."
    }

    /// W-FIX1 BUG-03: the hub's amber GO — the session plus its trimmed prescription.
    static func autoRegulatedMorning(_ v: VerdictParts) -> String {
        let head = v.session.isEmpty ? "Today's session" : v.session
        guard let prescription = autoRegulatedPrescription(v) else {
            return "\(head), trimmed — keep it easy today."
        }
        return "\(head), trimmed: \(lowerFirst(prescription))"
    }

    static func reducedMorning(session: String) -> String {
        // `session` is the verdict's own post-dash text (e.g. "deload dose, not a day off") —
        // reused rather than restated, so the sentence stays honest to what evaluate() decided.
        let why = session.isEmpty ? "" : " (\(session))"
        return "Keep loads light, skip progression attempts, and eat at maintenance today\(why)."
    }

    static func modifiedMorning(session: String) -> String {
        // The swap itself IS the concrete action — surface it instead of re-deriving one.
        session.isEmpty
            ? "Today's session was swapped for a safer alternative."
            : "Today's session was swapped: \(session)."
    }

    static let refluxSafeCarbs = "rice, potato, banana, or berries"

    /// Takes the two numbers rather than the DTO so the branch is testable independently of the
    /// wire decoding (see `InsightSentenceTests`'s note on `carbs_3d_avg`).
    static func carbWatch(carbs3dAvg: Double?, floor: Double) -> String? {
        guard let c3 = carbs3dAvg, c3 < floor else { return nil }
        return "Glycogen watch: 3-day carbs avg \(whole(c3))g is under the \(whole(floor))g floor — front-load reflux-safe carbs (\(refluxSafeCarbs)) before ~15:00."
    }

    // MARK: - Biggest-lever tier

    /// Below this gap (grams) the shortfall is day-to-day noise, not a lever worth a whole line.
    static let proteinGapMinG: Double = 10

    static func proteinGap(avgProtein7d: Double?, avgWeightKg: Double?) -> String? {
        guard let protein = avgProtein7d, let weight = avgWeightKg, weight != 0 else { return nil }
        let goalG = (weight * defaultKpiConfig.progressProteinPerKg).rounded()
        let gap = goalG - protein
        guard gap >= proteinGapMinG else { return nil }
        return "Protein is running \(whole(gap))g under your \(whole(goalG))g target this week — front-load it earlier in the day."
    }

    /// Below this, the deficit-implied weekly trend is too flat to call a lever.
    static let weightTrendMinKg: Double = 0.05

    static func weightTrend(estWeeklyWeightChangeKg: Double?) -> String? {
        guard let kg = estWeeklyWeightChangeKg, abs(kg) >= weightTrendMinKg else { return nil }
        let dir = kg < 0 ? "down" : "up"
        return "Weight is trending \(dir) about \(String(format: "%.2f", abs(kg))) kg/week on the current 7-day deficit."
    }

    // MARK: - Fallback tier — never empty

    public static let noVerdictCopy = "No verdict yet — sync to see today's readiness call."

    static func fallback(_ morning: MorningResponse) -> String {
        guard let verdict = morning.verdict, !verdict.isEmpty else { return noVerdictCopy }
        let v = verdictParts(verdict)
        let word = verdictUserWord(v)
        return v.session.isEmpty ? word : "\(word) — \(v.session)."
    }

    // MARK: - Helpers

    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// `Math.round(n)` -> a plain grouped-free integer string (the oracle interpolates the raw number).
    static func whole(_ value: Double) -> String { String(Int(value.rounded())) }
}
