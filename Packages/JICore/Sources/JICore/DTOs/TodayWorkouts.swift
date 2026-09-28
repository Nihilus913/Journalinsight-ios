import Foundation

/// W-FIX7 F7-1 (S1): a workout Apple Health holds for today, read ON THE PHONE (no hub path —
/// Toby 2026-09-28 "read from Apple Health directly"). JIHealthKit's `HKTodayWorkoutsReader`
/// fills it; JIFeatures never imports HealthKit.
public nonisolated struct TodayWorkout: Codable, Sendable, Equatable, Hashable {
    /// Strength / cardio / anything else — what a planned session is matched against.
    public enum Kind: String, Codable, Sendable, Equatable, Hashable {
        case strength, cardio, other
    }

    public var kind: Kind
    /// The activity in words ("Traditional strength", "Run", "Cycling").
    public var activityName: String
    public var start: Date
    public var end: Date
    /// The app that wrote it ("Bevel", "Workout"); nil when Health does not name one.
    public var sourceName: String?

    public init(kind: Kind, activityName: String, start: Date, end: Date, sourceName: String?) {
        self.kind = kind; self.activityName = activityName; self.start = start; self.end = end; self.sourceName = sourceName
    }

    /// Whole minutes, never negative.
    public var durationMinutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }

    /// "Traditional strength · 52 min · Bevel" (the source is left out when Health names none).
    public var summary: String {
        [activityName, "\(durationMinutes) min", sourceName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Reads today's workouts (local calendar day, every source). Empty = none today, or Health not
/// readable — the session then stays as it was (never a fabricated "done").
public protocol TodayWorkoutsProviding: Sendable {
    func todayWorkouts() async throws -> [TodayWorkout]
}

/// What today's planned session is, for matching.
public nonisolated enum PlannedSessionKind: Sendable, Equatable {
    case strength, cardio, rest, unknown

    /// Words that make a session a lifting session ("Day 1 Full Upper + Z2 40min" is strength —
    /// the lift is the session; the Z2 is its finisher).
    static let strengthWords = ["upper", "lower", "full body", "strength", "lift", "push", "pull", "legs"]
    static let cardioWords = ["z2", "zone 2", "interval", "run", "cardio", "ride", "bike", "cycl", "row", "swim", "walk", "long", "tempo", "hiit"]

    /// Classifies a session label; "Rest" → `.rest`, nothing recognisable → `.unknown`.
    public static func classify(_ label: String?) -> PlannedSessionKind {
        guard let text = label?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return .unknown }
        if text.hasPrefix("rest") { return .rest }
        if strengthWords.contains(where: { text.contains($0) }) { return .strength }
        if cardioWords.contains(where: { text.contains($0) }) { return .cardio }
        return .unknown
    }
}

/// F7-1: today's planned session against today's Apple Health workouts.
/// - `.done`: a workout of the planned kind (strength ↔ traditional/functional strength; cardio ↔
///   run/cycle/walk/elliptical/rower/…) — the session is done.
/// - `.otherActivity`: a workout that does not match — shown as "other activity", session stays open.
/// - `.none`: no workout today — everything stays as it was.
public nonisolated enum SessionCompletion: Sendable, Equatable {
    case done(TodayWorkout)
    case otherActivity(TodayWorkout)
    case none

    public static func resolve(planned: PlannedSessionKind, workouts: [TodayWorkout]) -> SessionCompletion {
        let sorted = workouts.sorted { $0.start < $1.start }
        let wanted: TodayWorkout.Kind? = switch planned {
        case .strength: .strength
        case .cardio: .cardio
        case .rest, .unknown: nil
        }
        // The longest matching workout is the session (a warm-up walk never outranks the lift).
        if let wanted, let hit = sorted.filter({ $0.kind == wanted }).max(by: { $0.durationMinutes < $1.durationMinutes }) {
            return .done(hit)
        }
        if let other = sorted.last { return .otherActivity(other) }
        return .none
    }

    public var isDone: Bool { if case .done = self { true } else { false } }

    public var workout: TodayWorkout? {
        switch self {
        case .done(let w), .otherActivity(let w): w
        case .none: nil
        }
    }

    /// The status line: "Done · Traditional strength · 52 min · Bevel", "Other activity · Walk · 30 min · Watch".
    public var statusText: String? {
        switch self {
        case .done(let w): "Done · \(w.summary)"
        case .otherActivity(let w): "Other activity · \(w.summary)"
        case .none: nil
        }
    }
}
