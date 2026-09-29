import Foundation
import SwiftUI
import JICore
import JICompute
import JIDesign

// B-57 W5 C4 — what the Day's NEXT card (board 1/02) and Decide's session row (board 1/01) take from
// the progression rule and the week. Pure helpers + the one "Progression due" callout view; the
// NEXT card itself stays TodayView's W-GUI card (one card, no second "NEXT" surface). Display-only:
// logging and the weight write-back stay B-38.

public nonisolated struct DaySessionLine: Equatable, Sendable {
    public let name: String
    public let from: String?
    public let to: String
    public init(name: String, from: String?, to: String) { self.name = name; self.from = from; self.to = to }
}

public nonisolated struct DaySessionCallout: Equatable, Sendable {
    public let title: String
    public let body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
}

public nonisolated struct DaySessionCardModel: Equatable, Sendable {
    public let title: String
    public let lines: [DaySessionLine]
    public let more: String?
    public let callout: DaySessionCallout?
}

/// Today's assigned strength session in the week (nil on a cardio or rest day, or with no week).
public nonisolated func todaysStrengthSession(_ week: TrainingWeekSummary?) -> String? {
    week?.days.first { $0.isToday && $0.kind == .strength }?.sessionName
}

/// "Week: 1 of 4 sessions"; "—" for the count while no gate row of this week is on the phone.
public nonisolated func dayWeekFooterText(_ week: TrainingWeekSummary?) -> String? {
    guard let week, week.planTotal > 0 else { return nil }
    return "Week: \(week.planDone.map(String.init) ?? "—") of \(week.planTotal) sessions"
}

/// The Day footer's "Week review" value: "1 of 4 sessions" from the week, else the W-GUI reason.
public nonisolated func dayWeekReviewValue(_ week: TrainingWeekSummary?) -> String {
    guard let week, week.planTotal > 0 else { return DayFooterRow.weekReview.value }
    return "\(week.planDone.map(String.init) ?? "—") of \(week.planTotal) sessions"
}

/// "session 2 of 4" — only while today's session is still to do and the count is known.
public nonisolated func daySessionOrdinal(_ week: TrainingWeekSummary?) -> String? {
    guard let week, week.planTotal > 0, let done = week.planDone,
          !(week.days.first { $0.isToday }?.done ?? false), done < week.planTotal else { return nil }
    return "session \(done + 1) of \(week.planTotal)"
}

/// Board 1/02 "NEXT": title with "session n of N", the first two lifts (50.0 → 52.5 when due),
/// "+k more · s sets", and the first due lift as the callout.
public nonisolated func daySessionCardModel(sessionName: String?, lifts: [LiftProgression], week: TrainingWeekSummary?) -> DaySessionCardModel? {
    guard let sessionName else { return nil }
    let title = daySessionOrdinal(week).map { "\(sessionName), \($0)" } ?? sessionName
    let lines = lifts.prefix(2).map { l in
        DaySessionLine(name: l.name, from: l.isDue ? l.currentKg.map { jiNumber($0, 1) } : nil,
                       to: l.nextKg.map { jiNumber($0, 1) } ?? "—")
    }
    var more: String?
    if lifts.count > 2 {
        let totalSets = lifts.compactMap(\.sets).reduce(0, +)
        more = "+\(lifts.count - 2) more" + (totalSets > 0 ? " · \(totalSets) sets" : "")
    }
    return DaySessionCardModel(title: title, lines: Array(lines), more: more, callout: dayProgressionCallout(lifts))
}

/// The first due lift, in words; nil when nothing is due (no callout at all).
public nonisolated func dayProgressionCallout(_ lifts: [LiftProgression]) -> DaySessionCallout? {
    lifts.first { $0.isDue }.flatMap { l in
        l.currentKg.map { DaySessionCallout(title: "Progression due on \(l.name.lowercased())",
                                            body: "All sets hit the target reps at \(jiNumber($0, 1)) kg last time.") }
    }
}

/// The NEXT card's exercise line with the rule applied: "50.0 → 52.5 kg · 3 sets" when due,
/// else the plan row's own load (PF-02, as Training lists it). `due` says whether to tint it.
public nonisolated func dayNextRowLoad(_ row: TrainingHeroRow, lifts: [LiftProgression]) -> (text: String, due: Bool) {
    guard let lift = lifts.first(where: { $0.exerciseId == row.id })
            ?? lifts.first(where: { Progression.normalizedName($0.name) == Progression.normalizedName(row.name) }),
          lift.isDue, let now = lift.currentKg, let next = lift.nextKg else { return (row.load, false) }
    let sets = lift.sets.map { " · \($0) sets" } ?? ""
    return ("\(jiNumber(now, 1)) → \(jiNumber(next, 1)) kg\(sets)", true)
}

/// W-FIX9 C-3: one NEXT lift row — name left, the plan right ("3 × 8 @ 50 kg", "… ✓" once every
/// planned set is logged), the logged count under it when short ("2 of 3 sets"), and the
/// progression rule's hint when it says so ("next: +2.5 kg at 3 × 10").
public nonisolated struct DayNextLiftRow: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let right: String
    public let logged: String?
    public let hint: String?
}

/// `loggedSets` are the day's sets from the hub (`/training/day/{today}` `exerciseSets`); with none
/// at all the rows claim nothing about what was done (an Apple workout carries no sets).
public nonisolated func dayNextLiftRows(_ rows: [TrainingHeroRow], lifts: [LiftProgression],
                                        loggedSets: [DayExerciseSet]) -> [DayNextLiftRow] {
    rows.map { row in
        let key = Progression.normalizedName(row.name)
        var right = row.prescription
        var logged: String?
        if !loggedSets.isEmpty, let planned = row.sets, planned > 0 {
            // W-FIX9 fixer (FIX9V-1): the progression rule's own match — name, category, and the
            // plan → Garmin aliases ("DB Shoulder Press" is logged as DUMBBELL_SHOULDER_PRESS).
            let mine = loggedSets.filter {
                Progression.matches(LoggedSet(exerciseName: $0.exerciseName, category: $0.exerciseCategory,
                                              setNumber: $0.setNumber, reps: $0.reps, weightKg: $0.weightKg), liftName: row.name)
            }
            let target = row.reps.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let hit = target.map { t in mine.allSatisfy { ($0.reps ?? 0) >= t } } ?? true
            if mine.count >= planned && hit { right += " ✓" } else { logged = "\(min(mine.count, planned)) of \(planned) sets" }
        }
        let lift = lifts.first(where: { $0.exerciseId == row.id }) ?? lifts.first(where: { Progression.normalizedName($0.name) == key })
        var hint: String?
        if let lift, lift.isDue, let now = lift.currentKg, let next = lift.nextKg, next > now {
            hint = ["next: +\(decideCompactNumber(next - now)) kg", row.setsTimesReps.map { "at \($0)" }]
                .compactMap { $0 }.joined(separator: " ")
        }
        return DayNextLiftRow(id: row.id, name: row.name, right: right, logged: logged, hint: hint)
    }
}

/// Decide's session row, right side (board 1/01): the first lift's next weight + "↑ Bench up" when due.
public nonisolated func decideSessionLift(_ lifts: [LiftProgression]) -> (kg: String, caption: String?)? {
    guard let first = lifts.first, let next = first.nextKg else { return nil }
    let word = first.name.split(separator: " ").first.map(String.init) ?? first.name
    return ("\(jiNumber(next, 1)) kg", first.isDue ? "↑ \(word) up" : nil)
}

// MARK: - DEV-10: a cardio session's NEXT line

public nonisolated enum DayCardioKind: Equatable, Sendable { case zone2, intervals }

/// The cardio parts of a session text ("Day 2 Full Upper + Z2 60min", "Long Zone 2 75-90min",
/// "Norwegian 4x4 intervals") with their minutes as written; strength parts are skipped.
public nonisolated func dayCardioParts(_ session: String) -> [(kind: DayCardioKind, minutes: String?)] {
    session.components(separatedBy: " + ").compactMap { raw in
        let part = raw.lowercased()
        let kind: DayCardioKind
        // W-FIX9: "swap intervals for easy Z2 30-40min" (the hub's MODIFIED swap) is the Z2 —
        // the same precedence as JICore `PlannedSessionKind.classify`.
        if part.contains("z2") || part.contains("zone 2") || part.contains("zone2") { kind = .zone2 }
        else if part.contains("4x4") || part.contains("interval") { kind = .intervals }
        else { return nil }
        let minutes = part.range(of: #"\d+(\s*[-–]\s*\d+)?\s*min"#, options: .regularExpression).map { r in
            part[r].replacingOccurrences(of: "min", with: "").replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "–")
        }
        return (kind, minutes)
    }
}

/// True when the session names a lifting part (anything that is not cardio or rest).
public nonisolated func daySessionHasStrengthPart(_ session: String) -> Bool {
    session.components(separatedBy: " + ").contains { raw in
        let t = raw.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !t.hasPrefix("—") && dayCardioParts(t).isEmpty
    }
}

/// DEV-10: the NEXT card's cardio line — "Zone 2 · 60 min · 139–159 bpm" from the user's zones, or
/// "· zones not set" (never a made-up range); intervals carry the user's cap only when one is set.
public nonisolated func dayCardioLine(session: String, zones: HrZones?, capBpm: Int?) -> String? {
    let parts = dayCardioParts(session)
    guard !parts.isEmpty else { return nil }
    return parts.map { p in
        switch p.kind {
        case .zone2:
            let range = zones.flatMap { $0.isValid ? "\($0.rangeText(2)) bpm" : nil } ?? "zones not set"
            return ["Zone 2", p.minutes.map { "\($0) min" }, range].compactMap { $0 }.joined(separator: " · ")
        case .intervals:
            return ["Intervals · 4 × 4 min", capBpm.map { "cap \($0) bpm" }].compactMap { $0 }.joined(separator: " · ")
        }
    }.joined(separator: "\n")
}

/// Board 1/02 "Progression due" callout inside the NEXT card.
public struct DayProgressionCalloutView: View {
    let callout: DaySessionCallout
    @Environment(\.jiTheme) private var theme
    public init(callout: DaySessionCallout) { self.callout = callout }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up").foregroundStyle(theme.color(.go)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(callout.title).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                Text(callout.body).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: theme.radius(.nested)).strokeBorder(theme.color(.hairlineNested)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.day.progression")
    }
}
