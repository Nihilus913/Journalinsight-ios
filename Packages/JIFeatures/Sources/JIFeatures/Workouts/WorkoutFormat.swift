import Foundation
import JICore
import JIDesign

/// W-B40 L2 — the library's and editor's text, kept out of the views so it is testable. Never a
/// zero for something that is not there: a lap-only workout has no minutes, so it says "lap"
/// instead of "0 min" (CLAUDE.md rule 5).
public nonisolated enum WorkoutFormat {
    public static let shortWeekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public static func duration(seconds: Int) -> String {
        seconds % 60 == 0 ? DurationFormat.minutes(seconds: seconds) : DurationFormat.clock(seconds: seconds)
    }

    /// "10:00", "4:00", "0:45".
    public static func clock(seconds: Int) -> String { DurationFormat.clock(seconds: seconds) }

    public static func distance(meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".0 km", with: " km") : "\(Int(meters.rounded())) m"
    }

    public static func end(_ end: StepEnd) -> String {
        switch end {
        case .time(let s): clock(seconds: s)
        case .distance(let m): distance(meters: m)
        case .lap: "Until lap"
        }
    }

    public static func target(_ target: StepTarget) -> String? {
        switch target {
        case .none: nil
        case .hrRange(let lo, let hi): "\(lo)–\(hi) bpm"
        case .hrZone(let z): "Zone \(z)"
        }
    }

    public static func purpose(_ p: WorkoutStepPurpose) -> String {
        switch p {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }

    public static func sport(_ s: WorkoutSport) -> String {
        switch s {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .strength: "Strength"
        }
    }

    public static func sportSymbol(_ s: WorkoutSport) -> String {
        switch s {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .strength: "dumbbell"
        }
    }

    /// "3 × 12 · 40 kg · rest 2:00"
    public static func strength(_ s: StrengthStep) -> String {
        var parts = ["\(s.sets) × " + (s.reps.map(String.init) ?? s.seconds.map { clock(seconds: $0) } ?? "—")]
        if let kg = s.weightKg, kg > 0 { parts.append(kg.rounded() == kg ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)) }
        if let r = s.restSeconds, r > 0 { parts.append("rest \(clock(seconds: r))") }
        return parts.joined(separator: " · ")
    }

    /// Total timed seconds of a segment (repeats expanded); nil when no step has a time end.
    public static func timedSeconds(_ seg: WorkoutSegment) -> Int? {
        let timed = seg.steps.compactMap(\.cardio).compactMap { c -> Int? in
            if case .time(let s) = c.end { return s * max(c.repeat, 1) } else { return nil }
        }
        return timed.isEmpty ? nil : timed.reduce(0, +)
    }

    /// The library row's second line.
    /// Cardio: "43 min · 10 steps · 100–175 bpm". Strength + run: "Strength · 2 exercises + Run 60 min".
    /// W-UITEST UT-2: a picker row's spoken label — the name AND its summary line, so VoiceOver
    /// (and XCUITest) hear "Tempo, 40 min · 2 steps · 100–150 bpm", not the name alone.
    public static func accessibilityLabel(_ t: WorkoutTemplate) -> String { "\(t.name), \(summary(t))" }

    public static func summary(_ t: WorkoutTemplate) -> String {
        let segments = t.effectiveSegments
        guard !segments.isEmpty else { return "No steps yet" }
        if segments.contains(where: { $0.sport == .strength }) {
            return segments.map { seg -> String in
                if seg.sport == .strength {
                    let n = seg.steps.compactMap(\.strength).count
                    return "Strength · \(n) exercise\(n == 1 ? "" : "s")"
                }
                return sport(seg.sport) + (timedSeconds(seg).map { " " + duration(seconds: $0) } ?? "")
            }.joined(separator: " + ")
        }
        let cardio = segments.flatMap { $0.steps.compactMap(\.cardio) }
        var parts: [String] = []
        let timed = segments.compactMap(timedSeconds)
        if !timed.isEmpty { parts.append(duration(seconds: timed.reduce(0, +)) + (cardio.contains { if case .time = $0.end { false } else { true } } ? "+" : "")) }
        let count = cardio.reduce(0) { $0 + max($1.repeat, 1) }
        parts.append("\(count) step\(count == 1 ? "" : "s")")
        if let hr = heartRateSpan(cardio) { parts.append(hr) }
        return parts.joined(separator: " · ")
    }

    /// "100–175 bpm" over absolute ranges, or "Zone 2" / "Zones 2–4"; nil = no targets.
    static func heartRateSpan(_ steps: [CardioStep]) -> String? {
        var los: [Int] = [], his: [Int] = [], zones: [Int] = []
        for s in steps {
            switch s.target {
            case .hrRange(let lo, let hi): los.append(lo); his.append(hi)
            case .hrZone(let z): zones.append(z)
            case .none: break
            }
        }
        if let lo = los.min(), let hi = his.max() { return "\(lo)–\(hi) bpm" }
        if let lo = zones.min(), let hi = zones.max() { return lo == hi ? "Zone \(lo)" : "Zones \(lo)–\(hi)" }
        return nil
    }

    public static func garminLabel(_ state: GarminState) -> String {
        switch state {
        case .current: "Garmin ✓"
        case .outdated: "Garmin outdated"
        case .notPushed: "Not on Garmin"
        }
    }

    public static func garminAccessibility(_ state: GarminState) -> String {
        switch state {
        case .current: "Garmin Connect has the current version"
        case .outdated: "Garmin Connect has an older version"
        case .notPushed: "Not pushed to Garmin Connect"
        }
    }

    /// "Mon · Fri" — nil when the template is on no plan day.
    public static func weekdays(_ days: [Int]) -> [String] {
        days.sorted().compactMap { shortWeekdays.indices.contains($0) ? shortWeekdays[$0] : nil }
    }

    /// One import bucket line: names when the hub sent them, else the count; "None" for zero.
    public static func bucket(_ b: ImportBucket) -> String {
        if !b.names.isEmpty { return b.names.joined(separator: ", ") }
        return b.count == 0 ? "None" : "\(b.count) workout\(b.count == 1 ? "" : "s")"
    }
}
