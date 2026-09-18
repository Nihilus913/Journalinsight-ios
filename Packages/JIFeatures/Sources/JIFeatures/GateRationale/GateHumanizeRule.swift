import Foundation

/// Port of the oracle `mobile/src/lib/humanizeRule.ts` (RN v1.18.2), verbatim in behaviour.
///
/// `GateResponse.triggeredRules` entries arrive as the debug strings HT's
/// `app/planning/service.py` `evaluate_kpi_gates()` builds —
/// `"avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))"` —
/// a log line, not copy a person should read. This is the pure translator: known metrics get a
/// plain-English sentence built from the parsed value/threshold/reason; anything else falls back to
/// a cleaned string that never leaks a raw snake_case field name.
///
/// The description itself can carry its own parenthetical, so the parser takes the LAST `)` as the
/// description's close (greedy `.*`) rather than the first — `GateInsight.parseTriggeredRule`
/// deliberately keeps the oracle's non-greedy `[^)]*`, which silently fails on those nested-paren
/// descriptions; this parser does not inherit that gap.
///
/// Deviation from the oracle, deliberate: RN's `toLocaleString(undefined, …)` reads the device
/// locale, which would make the ported cases locale-dependent in a test runner. `locale` is an
/// explicit parameter that defaults to the device locale (same behaviour at runtime); the ported
/// tests pass `en_US` so they assert the oracle's exact strings.
nonisolated struct ParsedGateRule: Equatable, Sendable {
    let metric: String
    let value: Double?
    let threshold: Double?
    let reason: String
}

nonisolated enum GateHumanizeRule {
    /// The count-qualifier the backend appends to some descriptions — "insufficient protein
    /// (5+ of 7 days)" — surfaced as its own clause rather than folded into the reason text.
    private static var countQualifier: Regex<(Substring, Substring)> {
        /\s*\((\d+\+ of \d+ days)\)\s*$/.ignoresCase()
    }

    static func parse(_ rule: String) -> ParsedGateRule? {
        let ruleRE = /^(\S+)\s+(\S+)\s+vs threshold\s+(\S+)\s+\((.*)\)$/
        guard let m = try? ruleRE.wholeMatch(in: rule) else { return nil }
        let verdictPrefix = /^(REDUCE|MAINTAIN|PROGRESS):\s*/.ignoresCase()
        let reason = String(m.4).replacing(verdictPrefix, with: "").trimmingCharacters(in: .whitespaces)
        return ParsedGateRule(
            metric: String(m.1),
            value: finiteNumber(String(m.2)),
            threshold: finiteNumber(String(m.3)),
            reason: reason
        )
    }

    /// `Number(raw)` + `Number.isFinite` — a value the hub could not derive arrives as "?" and must
    /// degrade to the em-dash placeholder, never `NaN`.
    private static func finiteNumber(_ raw: String) -> Double? {
        guard let n = Double(raw), n.isFinite else { return nil }
        return n
    }

    private static func splitQualifier(_ reason: String) -> (text: String, qualifier: String?) {
        guard let m = reason.firstMatch(of: countQualifier) else { return (reason, nil) }
        let text = reason.replacing(countQualifier, with: "").trimmingCharacters(in: .whitespaces)
        return (text, String(m.1))
    }

    /// `n.toLocaleString(undefined, { min/maxFractionDigits: decimals })`, or the em dash the app
    /// uses for every other missing value.
    static func fmt(_ n: Double?, _ decimals: Int = 0, locale: Locale) -> String {
        guard let n else { return "—" }
        return n.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    private static func qualifierClause(_ qualifier: String?) -> String {
        qualifier.map { " (\($0))" } ?? ""
    }

    static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    private static func humanizeMetricName(_ metric: String) -> String {
        let spaced = metric.replacingOccurrences(of: "_", with: " ")
        let dayed = spaced.replacing(/\b(\d+)d\b/) { m in "\(m.1)-day" }
        return capitalizeFirst(dayed.trimmingCharacters(in: .whitespaces))
    }

    /// Known rule/metric vocabulary — the four `kpi_target` metrics HT seeds
    /// (`app/db/migrations/003_fix_kpi_targets.sql`). `nil` falls back to the generic sentence.
    private static func metricSentence(
        metric: String, value: Double?, threshold: Double?, reasonText: String, qualifier: String?, locale: Locale
    ) -> String? {
        let q = qualifierClause(qualifier)
        switch metric {
        case "avg_kcal_7d":
            return "7-day intake averages \(fmt(value, locale: locale)) kcal against the \(fmt(threshold, locale: locale)) kcal floor\(q) — \(reasonText)."
        case "avg_protein_7d":
            return "7-day protein averages \(fmt(value, locale: locale))g against the \(fmt(threshold, locale: locale))g floor\(q) — \(reasonText)."
        case "sleep_score_7d":
            return "7-day sleep score averages \(fmt(value, locale: locale)) against the \(fmt(threshold, locale: locale)) floor\(q) — \(reasonText)."
        case "acwr":
            // Direction read off the numbers themselves (not the REDUCE/MAINTAIN verdict prefix) —
            // acwr fires REDUCE when too high (overreaching) and MAINTAIN when too low
            // (undertraining), so "above/below" has to follow value vs threshold.
            let dir = (value != nil && threshold != nil && value! > threshold!) ? "above" : "below"
            return "Training load ratio (ACWR) is \(fmt(value, 2, locale: locale)) — \(dir) the \(fmt(threshold, 2, locale: locale)) line — \(reasonText)."
        default:
            return nil
        }
    }

    /// Generic fallback for a rule whose metric isn't in the known vocabulary (still built from the
    /// parsed pieces when the rule string parses at all) or, failing that, a cleaned version of the
    /// raw string — underscores turned to spaces, never a raw field name shown as-is.
    private static func fallbackSentence(rule: String, parsed: ParsedGateRule?, locale: Locale) -> String {
        guard let parsed else {
            let cleaned = rule
                .replacingOccurrences(of: "_", with: " ")
                .replacing(/\s+/, with: " ")
                .trimmingCharacters(in: .whitespaces)
            return capitalizeFirst(cleaned)
        }
        let (text, qualifier) = splitQualifier(parsed.reason)
        let label = humanizeMetricName(parsed.metric)
        let valuePart = parsed.value != nil ? " is \(fmt(parsed.value, 1, locale: locale))" : ""
        let thresholdPart = parsed.threshold != nil ? " vs the \(fmt(parsed.threshold, 1, locale: locale)) threshold" : ""
        return "\(label)\(valuePart)\(thresholdPart)\(qualifierClause(qualifier)) — \(text)."
    }

    /// Translate one `triggeredRules` entry into a plain sentence. Pure and total — every input
    /// string produces readable output, never a throw and never a raw metric field name.
    static func humanize(_ rule: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard let parsed = parse(rule) else { return fallbackSentence(rule: rule, parsed: nil, locale: locale) }
        let (text, qualifier) = splitQualifier(parsed.reason)
        let sentence = metricSentence(
            metric: parsed.metric, value: parsed.value, threshold: parsed.threshold,
            reasonText: text, qualifier: qualifier, locale: locale
        )
        return sentence ?? fallbackSentence(rule: rule, parsed: parsed, locale: locale)
    }
}
