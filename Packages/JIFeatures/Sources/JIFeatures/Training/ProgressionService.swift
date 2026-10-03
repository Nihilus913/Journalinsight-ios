import Foundation
import Observation
import SwiftUI
import JICore
import JICompute
import JIPersistence

/// One lift's progression as the screens show it. `nextKg == nil` only when no weight is known.
public nonisolated struct LiftProgression: Sendable, Equatable, Identifiable {
    public let exerciseId: Int
    public let name: String
    public let sessionName: String
    public let currentKg: Double?
    public let nextKg: Double?
    public let state: ProgressionState?
    public let sets: Int?
    public var id: Int { exerciseId }
    public var isDue: Bool { if case .due = state { true } else { false } }
}

/// B-38 owns the switch; until it exists the rule is on (Toby 2026-09-22).
public nonisolated let progressionAutoSuggestKey = "training.progression.autoSuggest"

public nonisolated func progressionAutoSuggest(prefs: PrefStore?) -> Bool {
    ((try? prefs?.get(progressionAutoSuggestKey, as: Bool.self)) ?? nil) ?? true
}

/// The most recent `weekday` (Mon = 0) strictly before `today` — where last week's session sits.
public nonisolated func lastOccurrence(ofWeekday weekday: Int, before today: String) -> String? {
    guard (0...6).contains(weekday), let wd = try? CalendarMath.isoWeekday(today) else { return nil }
    let back = (wd - weekday + 7) % 7
    return try? CalendarMath.addDays(today, -(back == 0 ? 7 : back))
}

/// W-FIX5 W5-2: the progression rule's rep target from the plan text. A clean integer is itself;
/// a range ("6-12", "8–10") is double progression — the lift is due once every set reaches the
/// top of the range. Anything else ("max", "12-6") is no target. `parseRepsTarget` (JICore) stays
/// integer-only: it feeds the hub write, whose column is an integer.
public nonisolated func progressionRepsTarget(_ raw: String?) -> Int? {
    guard let raw else { return nil }
    let text = raw.trimmingCharacters(in: .whitespaces)
    if let n = Int(text) { return n > 0 ? n : nil }
    let parts = text.split(whereSeparator: { $0 == "-" || $0 == "–" || $0 == "—" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]), low > 0, high >= low else { return nil }
    return high
}

/// Pure: the plan rows, overlaid by the local strength state (a newer local weight wins), judged
/// against the last logged sets of each lift's session.
public nonisolated func liftProgressions(
    exercises: [Exercise], entries: [StrengthStateEntry], lastSessionSets: [String: [LoggedSet]], autoSuggest: Bool
) -> [LiftProgression] {
    exercises.map { ex in
        let entry = entries.first { $0.exerciseId == ex.exerciseId }
        let current = entry?.currentWeightKg ?? ex.currentWeightKg
        let sets = entry?.sets ?? ex.sets
        guard let current else {
            return LiftProgression(exerciseId: ex.exerciseId, name: ex.exerciseName, sessionName: ex.sessionName,
                                   currentKg: nil, nextKg: nil, state: nil, sets: sets)
        }
        let target = LiftTarget(name: ex.exerciseName, currentKg: current,
                                stepKg: entry?.progressionStepKg ?? ex.progressionStepKg, sets: sets,
                                repsTarget: entry?.repsTarget ?? progressionRepsTarget(ex.repsTarget))
        let state = Progression.evaluate(target: target, lastSession: lastSessionSets[ex.sessionName] ?? [], autoSuggest: autoSuggest)
        return LiftProgression(exerciseId: ex.exerciseId, name: ex.exerciseName, sessionName: ex.sessionName,
                               currentKg: current, nextKg: Progression.nextWorkingWeight(target: target, state: state),
                               state: state, sets: sets)
    }
}

/// B-57 W5: reads (never writes) the plan, the local strength state and the last logged day of
/// each assigned session, and applies `Progression`. Offline: cached rows only. Past days are
/// fetched once and then read from the cache (`training.day.<date>`, TrainingViewModel's key).
@Observable @MainActor
public final class ProgressionService {
    public private(set) var lifts: [LiftProgression] = []
    public private(set) var autoSuggest = true
    public private(set) var loadedDay: String?

    private let provider: (any TrainingProviding)?
    private let cache: OfflineCache
    private let strengthStore: StrengthStateStore
    private let prefs: PrefStore?
    private let today: () -> String

    public init(provider: (any TrainingProviding)?, cache: OfflineCache, strengthStore: StrengthStateStore = StrengthStateStore(),
                prefs: PrefStore?, today: @escaping () -> String = { DayKey.today(now: Date()).iso }) {
        self.provider = provider; self.cache = cache; self.strengthStore = strengthStore; self.prefs = prefs; self.today = today
    }

    public func refresh() async {
        let day = today()
        autoSuggest = progressionAutoSuggest(prefs: prefs)
        var exercises = (try? cache.get(TrainingViewModel.cacheKeys.exercises, as: [Exercise].self))?.value ?? []
        if let provider,
           let r = try? await SectionLoader.load(key: TrainingViewModel.cacheKeys.exercises, cache: cache, fetch: { try await provider.exercises() }),
           let v = r.value {
            exercises = v
        }
        let spine = (try? cache.get(TrainingViewModel.cacheKeys.planSessions, as: [PlanSessionOut].self))?.value ?? []
        var sets: [String: [LoggedSet]] = [:]
        for name in orderedSessionNames(exercises) {
            guard let weekday = weekStripSession(named: name, exercises: exercises, planSessions: spine).weekday,
                  let date = lastOccurrence(ofWeekday: weekday, before: day) else { continue }
            let key = "training.day.\(date)"
            var detail = (try? cache.get(key, as: TrainingDayDetail.self))?.value
            if detail == nil || detail?.exerciseSets.isEmpty == true, let provider,
               let r = try? await SectionLoader.load(key: key, cache: cache, fetch: { try await provider.trainingDay(date: date) }),
               let v = r.value {
                detail = v
            }
            if let detail {
                sets[name] = detail.exerciseSets.map {
                    LoggedSet(exerciseName: $0.exerciseName, category: $0.exerciseCategory, setNumber: $0.setNumber, reps: $0.reps, weightKg: $0.weightKg)
                }
            }
        }
        lifts = liftProgressions(exercises: exercises, entries: strengthStore.entries(), lastSessionSets: sets, autoSuggest: autoSuggest)
        loadedDay = day
    }

    /// Cheap from any card's `.task`: at most one refresh per day.
    public func refreshIfNeeded() async {
        if loadedDay != today() { await refresh() }
    }

    public func lifts(forSession name: String?) -> [LiftProgression] {
        guard let name else { return [] }
        let parts = Set(name.components(separatedBy: " + "))
        return lifts.filter { parts.contains($0.sessionName) }
    }

    public func lift(named name: String) -> LiftProgression? {
        let n = Progression.normalizedName(name)
        return lifts.first { Progression.normalizedName($0.name) == n }
    }
}

public extension EnvironmentValues {
    /// B-57 W5: set by the App (nil = previews/tests → no progression shown).
    @Entry var progression: ProgressionService?
}
