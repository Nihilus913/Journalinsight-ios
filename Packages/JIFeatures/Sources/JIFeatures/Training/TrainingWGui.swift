import Foundation
import JICore
import JIDesign

// W-GUI TR1 — Training (mockup 04): the strip legend, the plan summary line, the zones card
// and the progression caption, all pure. No numbers are invented: zones and the cap are the
// user's input and read "— none set" until W4 lands the store (plan §B).

/// Under the week strip: what the three dot states mean (the strip's existing states).
public nonisolated let trainingStripLegend = "green = done · outline = today · grey = planned"

/// "Full upper ×4 · Z2 60min" — the plan's session names, de-duplicated, in plan order.
public nonisolated func trainingPlanSummary(sessionNames: [String]) -> String? {
    var seen: [String] = []
    for n in sessionNames.map({ $0.trimmingCharacters(in: .whitespaces) }) where !n.isEmpty && !seen.contains(n) { seen.append(n) }
    return seen.isEmpty ? nil : seen.joined(separator: " · ")
}

/// "Next strength · Sat" — the next planned strength day's weekday word, else just the header.
public nonisolated func trainingNextStrengthHeader(weekdayWord: String?) -> String {
    weekdayWord.map { "Next strength · \($0)" } ?? "Next strength"
}

public nonisolated struct TrainingZoneRow: Equatable, Sendable, Identifiable {
    public let id: String, title: String, subtitle: String, value: String
}

/// The zones card — every value the user's own input; none set yet → "— none set" (never a
/// seeded number); Zone 5 is not a target in this plan.
public nonisolated func trainingZoneRows(cap: Double?, zone2: ClosedRange<Double>?) -> [TrainingZoneRow] {
    [
        TrainingZoneRow(id: "cap", title: "HR cap", subtitle: "Set by you · re-check with your clinician",
                        value: cap.map { "\(jiNumber($0, 0)) bpm" } ?? "— none set"),
        TrainingZoneRow(id: "z2", title: "Zone 2", subtitle: "Set by you",
                        value: zone2.map { "\(jiNumber($0.lowerBound, 0))–\(jiNumber($0.upperBound, 0))" } ?? "— none set"),
        TrainingZoneRow(id: "z5", title: "Zone 5", subtitle: "Not a target in this plan", value: "—"),
    ]
}

public nonisolated let trainingProgressionCaption = "Double progression: add 2.5 kg once all sets hit the top of the range. Working weights come from your log, not a formula."
