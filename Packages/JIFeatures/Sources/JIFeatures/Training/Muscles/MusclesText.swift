import Foundation
import JICompute

/// B-90 p5 — every string the Muscles surfaces print, pure so tests pin the wording (no number
/// without its reason; subtitles never wrap mid-phrase — each phrase is its own one-line Text).
nonisolated enum MusclesText {
    static func dayTime(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }

    /// "Last: Upper B · Wed 18:40" — its own line on the card and the screen hero.
    static func lastLine(_ s: MusclesSummary, _ calendar: Calendar) -> String? {
        guard let at = s.lastSessionAt else { return nil }
        return "Last: \(s.lastSessionName ?? "Strength session") · \(dayTime(at, calendar))"
    }

    static func ago(_ hours: Double) -> String {
        hours < 96 ? "\(max(0, Int(hours.rounded(.down)))) h ago" : "\(Int((hours / 24).rounded(.down))) d ago"
    }

    /// "1 of 3 workouts per muscle" — one line, never split.
    static func calibrationLine(_ s: MusclesSummary) -> String {
        "\(s.calibrationProgress) of \(MuscleFreshness.calibrationWorkouts) workouts per muscle"
    }

    static func names(_ rows: [MuscleRowSummary]) -> String? {
        guard let first = rows.first else { return nil }
        return rows.count == 1 ? first.name : "\(first.name) + \(rows.count - 1) more"
    }

    /// The hero headline: the worst state leads.
    static func headline(_ s: MusclesSummary) -> String {
        switch s.phase {
        case .empty: return "No strength sessions yet"
        case .calibrating: return "Calibrating"
        case .populated:
            for state in [MuscleState.depleted, .fatigued] {
                let hit = s.rows.filter { $0.state == state }
                if let n = names(hit) { return "\(n) \(state.word.lowercased())" }
            }
            return "Tracked muscles recovered"
        }
    }

    static func rowDetail(_ r: MuscleRowSummary, _ calendar: Calendar) -> String {
        switch r.state {
        case .depleted, .fatigued:
            var parts: [String] = []
            if let h = r.hoursSince { parts.append(ago(h)) }
            if r.aboveP75 { parts.append(">P75") }
            if let f = r.freshBy { parts.append("fresh ~\(dayTime(f, calendar))") }
            return parts.joined(separator: " · ")
        case .recovered:
            var parts: [String] = []
            if let at = r.lastAt { parts.append(dayTime(at, calendar)) }
            if let h = r.hoursSince { parts.append(ago(h)) }
            return parts.joined(separator: " · ")
        case .calibrating(let n):
            return "\(n) of \(MuscleFreshness.calibrationWorkouts) workouts in 28 d"
        case .noData:
            return "No lifts logged"
        }
    }

    static func ratio(_ r: MuscleRowSummary) -> String {
        guard let ratio = r.ratio else { return "—" }
        return musclesNumber(ratio, 2) + (r.band == .high ? " over" : "")
    }

    static func load(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }

    static let howSteps: [(String, String)] = [
        ("Credit table", "Each lift credits its muscles: primary × 1.0, secondary × 0.5. One table for the logger, the library and this screen."),
        ("Load", "Load = reps × kg per set (bodyweight sets: 0.65 × your weight). RPE is not used."),
        ("7 vs 28 days", "Ratio = last 7 days ÷ the 28-day pace per week. Below 0.8 low, 0.8–1.3 productive, above 1.3 overreaching — the same bands as whole-body load."),
        ("Freshness", "Recovered after 48 h, or 72 h when the last load was above your own P75 for that muscle; fatigued from half that window, depleted before."),
        ("Calibrating", "A muscle needs 3 workouts in 28 days before a state is shown. No data means no number."),
        ("What does not count", "Garmin-only sets and runs are not on the phone yet; legs show No data until a leg lift is logged."),
    ]
}
