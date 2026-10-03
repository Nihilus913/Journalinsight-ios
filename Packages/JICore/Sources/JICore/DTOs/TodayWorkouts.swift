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
    /// W-FIX9 G1: the hub's `core.activity` id when this workout is (also) on the hub — the NEXT
    /// card finds its `DayActivity` (time in zone) by it. nil = only on the phone so far.
    public var hubActivityId: Int?

    public init(kind: Kind, activityName: String, start: Date, end: Date, sourceName: String?, hubActivityId: Int? = nil) {
        self.kind = kind; self.activityName = activityName; self.start = start; self.end = end; self.sourceName = sourceName
        self.hubActivityId = hubActivityId
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
    case strength, cardio, interval, rest, unknown

    /// Words that make a session a lifting session ("Day 1 Full Upper + Z2 40min" is strength —
    /// the lift is the session; the Z2 is its finisher).
    static let strengthWords = ["upper", "lower", "full body", "strength", "lift", "push", "pull", "legs"]
    static let cardioWords = ["z2", "zone 2", "interval", "run", "cardio", "ride", "bike", "cycl", "row", "swim", "walk", "long", "tempo", "hiit"]

    /// Classifies a session label; "Rest" → `.rest`, nothing recognisable → `.unknown`.
    public static func classify(_ label: String?) -> PlannedSessionKind {
        guard let text = label?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return .unknown }
        if text.hasPrefix("rest") { return .rest }
        if strengthWords.contains(where: { text.contains($0) }) { return .strength }
        // W-FIX9 (audit F3): intervals are their own kind — only a run or a ride completes them.
        // "swap intervals for easy Z2 30-40min" (the hub's MODIFIED session) is the easy Z2, not intervals.
        let easy = ["z2", "zone 2", "easy"].contains { text.contains($0) }
        if !easy, intervalWords.contains(where: { text.contains($0) }) { return .interval }
        if cardioWords.contains(where: { text.contains($0) }) { return .cardio }
        return .unknown
    }

    /// Words that make a cardio part an interval part ("Norwegian 4x4 intervals", "HIIT").
    static let intervalWords = ["interval", "4x4", "hiit"]
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

    /// The rule by planned kind (Training's week strip knows a day's kind, not its label).
    public static func resolve(planned: PlannedSessionKind, workouts: [TodayWorkout]) -> SessionCompletion {
        let parts: [SessionPart] = switch planned {
        case .strength: [.strength]
        case .cardio: [.steadyCardio]
        case .interval: [.intervals]
        case .rest, .unknown: []
        }
        return progress(parts: parts, workouts: workouts).completion
    }

    /// W-SSOT-1 SS-2: by planned kind, preferring the hub's `completion` when present.
    public static func resolve(planned: PlannedSessionKind, workouts: [TodayWorkout], hub: HubCompletion?) -> SessionCompletion {
        guard let hub else { return resolve(planned: planned, workouts: workouts) }
        return progress(hub: hub, workouts: workouts).completion
    }

    /// The rule by session label ("Day 1 Full Upper + Z2 40min") — the lead part decides.
    public static func resolve(sessionLabel: String?, workouts: [TodayWorkout]) -> SessionCompletion {
        progress(sessionLabel: sessionLabel, workouts: workouts).completion
    }

    /// W-FIX9 G5: every part of the planned session against today's workouts.
    public static func progress(sessionLabel: String?, workouts: [TodayWorkout]) -> SessionProgress {
        progress(parts: SessionPart.parts(of: sessionLabel), workouts: workouts)
    }

    /// W-SSOT-1 SS-2: the hub's `completion` when present (its plan + its rule decide the parts and
    /// everything the hub holds), else the label rule. A phone-only workout (not on the hub yet —
    /// `hubActivityId == nil`) can still fill a strength or interval part the hub has open, by the
    /// app's own `accepts` — never a Z2 part (W-B49C R-5: the hub judges Z2 by its zone share and the
    /// phone's workout has no HR; it shows as other activity until the hub has it).
    public static func progress(sessionLabel: String?, workouts: [TodayWorkout], hub: HubCompletion?) -> SessionProgress {
        guard let hub else { return progress(sessionLabel: sessionLabel, workouts: workouts) }
        return progress(hub: hub, workouts: workouts)
    }

    static func progress(hub: HubCompletion, workouts: [TodayWorkout]) -> SessionProgress {
        let sorted = workouts.sorted { $0.start < $1.start }
        let hubParts: [(SessionPart, HubCompletion.Part)] = hub.parts.compactMap { p in
            switch p.part {
            case "strength": (.strength, p)
            case "cardio": (hub.sessionType == "interval" ? .intervals : .steadyCardio, p)
            default: nil
            }
        }
        var used = Set<Int>()
        var statuses = hubParts.map { SessionPartStatus(part: $0.0, workout: nil, hubDone: $0.1.done) }
        // Hub-done parts first: the workout the hub names (by core.activity id).
        for (i, (_, hp)) in hubParts.enumerated() where hp.done {
            if let hit = sorted.indices.first(where: { !used.contains($0) && sorted[$0].hubActivityId.map(hp.activityIds.contains) == true }) {
                used.insert(hit); statuses[i].workout = sorted[hit]
            }
        }
        // Hub-open parts: only a phone-only workout may fill them (the hub already judged its own rows),
        // and never a Z2 part — W-B49C R-5 (B-85): Z2 is done by zone share, which only the hub knows.
        for (i, (part, hp)) in hubParts.enumerated() where !hp.done && part != .steadyCardio {
            let hit = sorted.indices
                .filter { !used.contains($0) && sorted[$0].hubActivityId == nil && part.accepts(sorted[$0]) }
                .max { sorted[$0].durationMinutes < sorted[$1].durationMinutes }
            if let hit { used.insert(hit); statuses[i].workout = sorted[hit] }
        }
        return SessionProgress(parts: statuses, latestWorkout: sorted.last)
    }

    /// THE match: each part takes the longest unused workout it accepts (a warm-up walk never
    /// outranks the lift; one workout never fills two parts).
    static func progress(parts: [SessionPart], workouts: [TodayWorkout]) -> SessionProgress {
        let sorted = workouts.sorted { $0.start < $1.start }
        var used = Set<Int>()
        let statuses = parts.map { part -> SessionPartStatus in
            let hit = sorted.indices
                .filter { !used.contains($0) && part.accepts(sorted[$0]) }
                .max { sorted[$0].durationMinutes < sorted[$1].durationMinutes }
            if let hit { used.insert(hit) }
            return SessionPartStatus(part: part, workout: hit.map { sorted[$0] })
        }
        return SessionProgress(parts: statuses, latestWorkout: sorted.last)
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

// MARK: - W-FIX9 G5: the parts of one planned session

/// One part of a planned session: the lift, a steady cardio block (Z2, a long run — a walk counts,
/// as the hub gate counts it) or intervals (a run or a ride only — audit F3, `morning_go.py`).
public nonisolated enum SessionPart: Sendable, Equatable, Hashable {
    case strength, steadyCardio, intervals

    /// "Day 1 Full Upper + Z2 40min" → [.strength, .steadyCardio]; "Rest" / unknown → [].
    public static func parts(of label: String?) -> [SessionPart] {
        guard let text = label?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              !text.lowercased().hasPrefix("rest") else { return [] }
        var out: [SessionPart] = []
        for piece in text.components(separatedBy: "+") {
            let part: SessionPart? = switch PlannedSessionKind.classify(piece) {
            case .strength: .strength
            case .interval: .intervals
            case .cardio: .steadyCardio
            case .rest, .unknown: nil
            }
            if let part, !out.contains(part) { out.append(part) }
        }
        return out
    }

    /// Whether `workout` fills this part.
    public func accepts(_ workout: TodayWorkout) -> Bool {
        switch self {
        case .strength: workout.kind == .strength
        case .steadyCardio: workout.kind == .cardio
        case .intervals: workout.kind == .cardio && workout.isRunOrRide
        }
    }

    /// How the summary line names the part ("Completed strength · Z2 open").
    public var shortName: String {
        switch self {
        case .strength: "strength"
        case .steadyCardio: "Z2"
        case .intervals: "intervals"
        }
    }
}

public nonisolated struct SessionPartStatus: Sendable, Equatable {
    public var part: SessionPart
    /// The workout that fills it; nil = still open (unless the hub says done — `hubDone`).
    public var workout: TodayWorkout?
    /// W-SSOT-1 SS-2: the hub's completion marked this part done (e.g. a Z2 day's step goal, or a
    /// hub row the phone cannot show as a workout).
    public var hubDone: Bool = false
    public var isDone: Bool { workout != nil || hubDone }
}

/// W-FIX9: the planned session's parts against today's workouts. `completion` is the lead part's
/// answer (what NEXT's "Done ·" line has said since F7-1); `isComplete` / `isPartial` feed the
/// summary line (C-1).
public nonisolated struct SessionProgress: Sendable, Equatable {
    public var parts: [SessionPartStatus]
    /// The last workout of the day, for "Other activity" when the lead part is open.
    public var latestWorkout: TodayWorkout?

    public var isComplete: Bool { !parts.isEmpty && parts.allSatisfy(\.isDone) }
    public var isPartial: Bool { parts.contains(where: \.isDone) && !isComplete }
    public var doneParts: [SessionPart] { parts.filter(\.isDone).map(\.part) }
    public var openParts: [SessionPart] { parts.filter { !$0.isDone }.map(\.part) }
    /// The workout that fills the lead part, else the first filled part.
    public var lead: TodayWorkout? { parts.first?.workout ?? parts.compactMap(\.workout).first }

    /// NEXT's status line — the lead part's line ("Done · …" / "Other activity · …"), except when a
    /// later part is what got done: "Z2 done · Outdoor Run · 36 min · Apple Health · strength open".
    public var statusText: String? {
        guard parts.first?.isDone == false, isPartial, let w = lead else { return completion.statusText }
        let done = doneParts.map(\.shortName).joined(separator: " + ")
        let open = openParts.map(\.shortName).joined(separator: " + ")
        return "\(done) done · \(w.summary) · \(open) open"
    }

    /// Any part done (NEXT ticks the line).
    public var anyDone: Bool { parts.contains(where: \.isDone) }

    public var completion: SessionCompletion {
        if let w = parts.first?.workout { return .done(w) }
        if let other = latestWorkout { return .otherActivity(other) }
        return .none
    }
}

// MARK: - W-FIX9 G1: the hub's core.activity rows (Garmin + Apple dso 4) as today's workouts

public extension TodayWorkout {
    /// ± 5 min — the hub's own overlap window (`healthWorkoutsNotOnHub` uses the same rule).
    static let sameWorkoutWindow: TimeInterval = 5 * 60

    /// Whether a workout starting at `start` is this one (the hub's copy of a Health workout).
    func isSameWorkout(startingAt start: Date) -> Bool {
        abs(start.timeIntervalSince(self.start)) <= Self.sameWorkoutWindow
    }

    /// A run or a ride (what completes an interval part) — by the activity's name.
    var isRunOrRide: Bool {
        let t = activityName.lowercased()
        return ["run", "cycl", "bik", "ride", "treadmill"].contains { t.contains($0) }
    }

    /// The hub's `type` ("traditional_strength_training", "running", "walking") in the HealthKit
    /// reader's kinds.
    static func kind(ofHubType type: String) -> Kind {
        let t = type.lowercased()
        if t.contains("strength") || t.contains("functional") { return .strength }
        let cardio = ["run", "cycl", "bik", "walk", "hik", "swim", "row", "elliptical", "stair", "step",
                      "cardio", "hiit", "high_intensity", "ski", "paddl", "jump_rope", "skat"]
        return cardio.contains { t.contains($0) } ? .cardio : .other
    }

    /// "traditional_strength_training" → "Traditional strength training".
    static func title(ofHubType type: String) -> String {
        let words = type.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return "Workout" }
        return first.uppercased() + words.dropFirst()
    }

    /// A hub row as a workout; nil without a start or a duration (never a guessed time).
    init?(hubActivity a: DayActivity) {
        guard let start = a.startDate, let seconds = a.durationSec, seconds.isFinite, seconds > 0 else { return nil }
        let name = a.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? Self.title(ofHubType: a.type)
        let source: String? = switch a.source { case "apple": "Apple Health"; case "garmin": "Garmin"; default: nil }
        self.init(kind: Self.kind(ofHubType: a.type), activityName: name, start: start,
                  end: start.addingTimeInterval(seconds), sourceName: source, hubActivityId: a.activityId)
    }

    /// Today's workouts from both sides: every Health row (it names the app, "Bevel"), tagged with
    /// its hub id when an Apple hub row is the same workout; plus every hub row the phone does not
    /// hold (a Garmin-only session, or an Apple one read on another device).
    static func merging(local: [TodayWorkout], hub: [DayActivity]) -> [TodayWorkout] {
        var claimed = Set<Int>()
        var out = local.map { w -> TodayWorkout in
            var w = w
            if let twin = hub.first(where: { $0.isAppleHealth && !claimed.contains($0.activityId)
                                             && $0.startDate.map(w.isSameWorkout(startingAt:)) == true }) {
                claimed.insert(twin.activityId)
                w.hubActivityId = twin.activityId
            }
            return w
        }
        out += hub.filter { !claimed.contains($0.activityId) }.compactMap(TodayWorkout.init(hubActivity:))
        return out.sorted { $0.start < $1.start }
    }
}
