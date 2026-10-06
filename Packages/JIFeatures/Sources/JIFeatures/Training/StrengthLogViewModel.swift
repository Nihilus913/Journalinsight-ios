import Foundation
import Observation
import SwiftUI
import JICore
import JICompute
import JIPersistence
import JIWorkouts

/// W-B38-A A-10 — one exercise of the selected training as the logger prefills it (decision:
/// "prefilled from the selected training — its exercises, sets, reps, weights").
public nonisolated struct StrengthLogLift: Sendable, Equatable, Identifiable {
    public let exerciseId: Int?
    public let exerciseKey: String
    public let sets: Int?
    public let repsTarget: String?
    public let currentKg: Double?
    public let stepKg: Double?
    /// `ProgressionService`'s next working weight (nil = not known).
    public let nextKg: Double?
    public var id: String { exerciseKey }

    public init(exerciseId: Int?, exerciseKey: String, sets: Int?, repsTarget: String?, currentKg: Double?, stepKg: Double?, nextKg: Double?) {
        self.exerciseId = exerciseId; self.exerciseKey = exerciseKey; self.sets = sets; self.repsTarget = repsTarget
        self.currentKg = currentKg; self.stepKg = stepKg; self.nextKg = nextKg
    }

    /// A rep target like "45s" / "60 sec" is a timed set (plank, carry).
    public var timedSeconds: Int? {
        guard let raw = repsTarget?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        for suffix in ["sec", "s"] where raw.hasSuffix(suffix) {
            if let n = Int(raw.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)), n > 0 { return n }
        }
        return nil
    }
    public var isTimed: Bool { timedSeconds != nil }
    /// W-FIX-P3 RG-67: no load prescribed (0 / nil kg, never a next weight) — pull-ups, push-ups, dips.
    public var isBodyweight: Bool { (currentKg ?? 0) <= 0 && (nextKg ?? 0) <= 0 }
}

/// The selected training's exercises (same pick as the hero: by session id, else by name), each
/// with the progression service's next weight. Pure.
public nonisolated func strengthLogLifts(exercises: [Exercise], session: PlannedSession?, progressions: [LiftProgression]) -> [StrengthLogLift] {
    guard let session else { return [] }
    let byId = exercises.filter { $0.sessionId == session.id }
    let picked = byId.isEmpty ? exercises.filter { $0.sessionName == session.name } : byId
    return picked.map { e in
        let p = progressions.first { $0.exerciseId == e.exerciseId }
        return StrengthLogLift(exerciseId: e.exerciseId, exerciseKey: e.exerciseName, sets: p?.sets ?? e.sets, repsTarget: e.repsTarget,
                               currentKg: p?.currentKg ?? e.currentWeightKg, stepKg: e.progressionStepKg, nextKg: p?.nextKg)
    }
}

/// Decision (Toby 2026-10-03): the exercise preview is the targeted muscle(s), no animation.
/// B-90 p1: the muscles come from the ONE table, `JICompute.MuscleMap` (keys = the catalogue + its
/// short aliases); an unknown exercise shows no preview (never a guess).
public nonisolated enum StrengthMuscles {
    public static func targets(for exerciseKey: String) -> [String]? {
        MuscleMap.weights(forExercise: exerciseKey).map(MuscleMap.displayNames)
    }
}

/// W-FIX13 F-3c — how a lift is loaded. A dumbbell's logged weight is ONE dumbbell (per hand)
/// with no bar; everything else keeps the barbell math (bar + plates on two sides).
public nonisolated enum StrengthLoad: Sendable, Equatable {
    case barbell
    case dumbbell

    public static func of(_ exerciseKey: String) -> StrengthLoad {
        let name = Progression.normalizedName(exerciseKey)
        return name.hasPrefix("db ") || name.contains("dumbbell") ? .dumbbell : .barbell
    }

    /// W-FIX-P3 RG-67: a kettlebell ("KB Swing 12 kg") is one fixed weight — no plates to load.
    public static func isFixedWeight(_ exerciseKey: String) -> Bool {
        let name = Progression.normalizedName(exerciseKey)
        return name.hasPrefix("kb ") || name.contains("kettlebell")
    }
}

/// The plate inventory the logger computes with (decision: standard plates + the 1.25 / 2.5 kg
/// microplates by default, editable). Stored in `PrefStore`.
public nonisolated struct PlateInventory: Codable, Sendable, Equatable {
    public var barKg: Double
    public var pairs: [Double]
    public static let `default` = PlateInventory(barKg: PlateMath.defaultBarKg, pairs: PlateMath.defaultPairs)
    public static let prefKey = "training.strength.plates"
    public init(barKg: Double, pairs: [Double]) { self.barKg = barKg; self.pairs = pairs }

    /// "25, 20, 15, 10, 10, 5" → pairs; nil when a value is not a positive number.
    public static func parsePairs(_ text: String) -> [Double]? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }).map { $0.replacingOccurrences(of: "kg", with: "") }
            .filter { !$0.isEmpty }
        let values = parts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard !values.isEmpty, values.count == parts.count, values.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        return values.sorted(by: >)
    }
}

/// W-B38-A A-10 — the iPhone strength logger. Local-first: every log / edit / delete writes
/// `StrengthSessionLogStore` and enqueues the matching `strength` outbox row BEFORE the hub is
/// asked; the screen then tries one drain. Complete sends the explicit `advance` list the app
/// computed with `JICompute.Progression` over THIS session's sets — only when the
/// `progressionAutoSuggest` toggle is on (off → `[]`, the hub moves nothing).
@Observable @MainActor
public final class StrengthLogViewModel {
    public struct Card: Identifiable, Equatable {
        public let lift: StrengthLogLift
        public var sets: [StrengthSetLog]
        public var defaults: LastSetDefaults.Value
        public var lastTime: [StrengthSetLog]
        public var id: String { lift.id }
        public var muscles: [String]? { StrengthMuscles.targets(for: lift.exerciseKey) }
        /// W-FIX-P2 RG-27: the next set's number = max(set_index)+1 (never `count+1`, which reuses
        /// an existing number after a middle set is deleted).
        public var nextSetIndex: Int { (sets.map(\.setIndex).max() ?? 0) + 1 }
    }

    public private(set) var cards: [Card] = []
    public private(set) var session: StrengthSessionLog?
    public private(set) var pendingCount = 0
    public private(set) var syncNote: String?
    public private(set) var completedAdvance: [StrengthAdvance]?
    public private(set) var error: String?
    public var timer = SetTimer() {
        // B-43 P1: every countdown change (start, +30 s, Skip/Dismiss, complete) re-plans the rest-end
        // notification that alerts while the phone is locked / the app is backgrounded.
        didSet { if timer != oldValue { restAlert?.sync(timer, exercise: restExercise, now: now()) } }
    }
    /// B-43 P1: the background rest-end alert (nil in tests / previews that don't check it).
    @ObservationIgnored public let restAlert: RestEndAlert?
    /// The exercise of the set that started the running rest (named in the alert body).
    @ObservationIgnored private var restExercise: String?
    public private(set) var plates: PlateInventory
    public var autoSuggest: Bool {
        didSet { try? prefs?.set(progressionAutoSuggestKey, autoSuggest) }
    }
    /// The rest the timer starts after a logged set.
    public var restSeconds = 90
    /// RG-76: true once the rest-alert permission ask came back denied/failed — the logger shows
    /// `RestEndAlert.offNotice` instead of silently dropping the Bool.
    public private(set) var restAlertsOff = false

    /// RG-76: runs the permission ask (default: `RestEndAlert.requestAuthorization()`) and keeps
    /// its answer as visible state.
    public func requestRestAlertPermission(_ ask: () async -> Bool = { await RestEndAlert.requestAuthorization() }) async {
        restAlertsOff = !(await ask())
    }

    public let sessionName: String?
    private let sessionId: Int?
    private let store: StrengthSessionLogStore
    private let queue: StrengthOutbox?
    private let provider: (any TrainingProviding)?
    private let prefs: PrefStore?
    private let today: () -> String
    private let now: () -> Date
    /// B-43 P2: sessionOpen nudge after each set, both training nudges dropped on complete.
    private let reminders: (any WorkoutSessionReminding)?
    @ObservationIgnored var reminderTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var drainObserver: (any NSObjectProtocol)?   // unsafe: written once in init, read in deinit only

    public init(lifts: [StrengthLogLift], sessionId: Int?, sessionName: String?, store: StrengthSessionLogStore,
                outbox: Outbox?, provider: (any TrainingProviding)?, prefs: PrefStore?,
                today: @escaping () -> String, now: @escaping () -> Date = Date.init, restAlert: RestEndAlert? = nil,
                reminders: (any WorkoutSessionReminding)? = nil) {
        self.restAlert = restAlert
        self.reminders = reminders
        self.sessionId = sessionId; self.sessionName = sessionName; self.store = store; self.provider = provider
        self.prefs = prefs; self.today = today; self.now = now
        self.queue = (outbox != nil && provider != nil) ? StrengthOutbox(outbox: outbox!, provider: provider!) : nil
        self.autoSuggest = progressionAutoSuggest(prefs: prefs)
        self.plates = ((try? prefs?.get(PlateInventory.prefKey, as: PlateInventory.self)) ?? nil) ?? .default
        // F-3a: the app-wide `OutboxDrainer` holds its own `StrengthOutbox`; when ANY pass ends the
        // pending count (and its note) is re-read, so the note never outlives the queue.
        drainObserver = NotificationCenter.default.addObserver(forName: StrengthOutbox.didDrain, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPending() }
        }
        self.cards = lifts.map { Card(lift: $0, sets: [], defaults: LastSetDefaults.resolve(sessionSets: [], planKg: $0.nextKg ?? $0.currentKg, planReps: progressionRepsTarget($0.repsTarget), lastSessionSets: []), lastTime: []) }
    }

    deinit { if let drainObserver { NotificationCenter.default.removeObserver(drainObserver) } }

    // MARK: lifecycle

    /// Resumes today's open session (if any) from the local store; nothing is created until the
    /// first set is logged (an opened-and-abandoned screen leaves no empty session on the hub).
    public func load() async {
        let day = today()
        session = try? store.openSession(date: day)
        for i in cards.indices {
            cards[i].lastTime = (try? store.lastSets(exerciseKey: cards[i].lift.exerciseKey, before: day)) ?? []
        }
        reloadSets()
        refreshPending()
        await fillLastTimeFromHub()
        await sync()
    }

    /// Gap #29: when the phone has no earlier session of a lift, ask the hub for its last sets.
    /// F-3b: "Last time" is never today — the hub's last-sets is its NEWEST session, which is today's
    /// once today's sets reached it; then the newest hub session dated before today is used.
    private func fillLastTimeFromHub() async {
        guard let provider else { return }
        let day = today()
        let todaysIds = Set(((try? store.sessions(from: day, to: day)) ?? []).flatMap { (try? store.sets(sessionClientId: $0.clientId)) ?? [] }.map(\.clientId))
        var earlier: [StrengthSessionOut]?
        for i in cards.indices where cards[i].lastTime.isEmpty {
            let key = cards[i].lift.exerciseKey
            guard var sets = try? await provider.strengthLastSets(exerciseKey: key), !sets.isEmpty else { continue }
            if sets.contains(where: { $0.clientId.map(todaysIds.contains) == true }) {
                if earlier == nil {
                    earlier = ((try? await provider.strengthSessions(from: "2000-01-01", to: day)) ?? [])
                        .filter { ($0.date ?? day) < day }
                        .sorted { ($0.date ?? "", $0.startedAt ?? "") > ($1.date ?? "", $1.startedAt ?? "") }
                }
                let wanted = Progression.normalizedName(key)
                sets = (earlier ?? []).lazy.map { ($0.sets ?? []).filter { Progression.normalizedName($0.exerciseKey) == wanted } }
                    .first { !$0.isEmpty }?.sorted { ($0.setIndex ?? 0) < ($1.setIndex ?? 0) } ?? []
                guard !sets.isEmpty else { continue }
            }
            cards[i].lastTime = sets.map { s in
                StrengthSetLog(clientId: s.clientId ?? UUID().uuidString.lowercased(), sessionClientId: "", exerciseKey: s.exerciseKey,
                               exerciseId: s.exerciseId, setIndex: s.setIndex ?? 0, kind: s.kind == "timed" ? .timed : .reps,
                               reps: s.reps, weightKg: s.weightKg, durationS: s.durationS, rpe: s.rpe, performedAt: s.performedAt ?? "")
            }
        }
        recomputeDefaults()
    }

    // MARK: library (W-B38-B B-10)

    /// Adds an exercise picked in the exercise library to this session (once). It carries no plan
    /// target — no weight is invented; defaults come from its last time, if any.
    public func addExercise(_ option: ExerciseOption) {
        guard !cards.contains(where: { $0.lift.exerciseKey == option.key }) else { return }
        let lift = StrengthLogLift(exerciseId: nil, exerciseKey: option.key, sets: nil, repsTarget: nil, currentKg: nil, stepKg: nil, nextKg: nil)
        let last = (try? store.lastSets(exerciseKey: option.key, before: today())) ?? []
        cards.append(Card(lift: lift, sets: [], defaults: LastSetDefaults.resolve(sessionSets: [], planKg: nil, planReps: nil, lastSessionSets: []), lastTime: last))
        reloadSets()
    }

    // MARK: sets

    /// Logs one set of `exerciseKey`. A reps set needs reps > 0, a timed set a duration > 0
    /// (the hub refuses either missing with a 422); weight / RPE are optional.
    @discardableResult
    public func logSet(exerciseKey: String, weightKg: Double?, reps: Int?, durationS: Int? = nil, rpe: Double? = nil) -> StrengthSetLog? {
        guard let card = cards.first(where: { $0.lift.exerciseKey == exerciseKey }) else { return nil }
        // W-FIX-P2 RG-26 (B-52): a completed session takes no more sets — no orphan second session.
        guard canLogSet else { error = "This session is complete."; return nil }
        let timed = card.lift.isTimed
        guard timed ? (durationS ?? 0) > 0 : (reps ?? 0) > 0 else { error = timed ? "Enter the time held." : "Enter the reps."; return nil }
        error = nil
        // W-FIX-P0 RG-01 (B-117): a session row that could not be written means no set either —
        // the set's FK would orphan it and the hub would get a createSession the phone never kept.
        guard let session = ensureSession() else { return nil }
        let set = StrengthSetLog(sessionClientId: session.clientId, exerciseKey: exerciseKey, exerciseId: card.lift.exerciseId,
                                 setIndex: card.nextSetIndex, kind: timed ? .timed : .reps,
                                 reps: timed ? nil : reps, weightKg: Self.kg(weightKg), durationS: timed ? durationS : nil,
                                 rpe: rpe, performedAt: now().ISO8601Format())
        do { try store.upsertSet(set) } catch { self.error = "Could not save the set on this phone."; return nil }
        queue?.enqueue(.logSet(session: session.clientId, Self.body(set)))
        reloadSets()
        restExercise = exerciseKey
        timer = timer.startingRest(seconds: restSeconds, at: now())
        if let reminders {
            let at = now()
            reminderTask = Task { await reminders.setLogged(at: at) }
        }
        afterWrite()
        return set
    }

    public func editSet(_ set: StrengthSetLog, weightKg: Double?, reps: Int?, durationS: Int? = nil, rpe: Double?) {
        var edited = set
        edited.weightKg = Self.kg(weightKg); edited.rpe = rpe
        if set.kind == .timed { guard let d = durationS, d > 0 else { return }; edited.durationS = d }
        else { guard let r = reps, r > 0 else { return }; edited.reps = r }
        do { try store.upsertSet(edited) } catch { self.error = "Could not save the edit on this phone."; return }
        queue?.enqueue(.updateSet(session: set.sessionClientId, Self.body(edited)))
        reloadSets()
        afterWrite()
    }

    public func deleteSet(_ set: StrengthSetLog) {
        do { try store.deleteSet(clientId: set.clientId) } catch { self.error = "Could not delete the set on this phone."; return }
        queue?.enqueue(.deleteSet(session: set.sessionClientId, clientId: set.clientId))
        reloadSets()
        afterWrite()
    }

    // MARK: complete

    /// The explicit progression moves for THIS session (toggle off → none).
    public func advanceList() -> [StrengthAdvance] {
        guard autoSuggest else { return [] }
        return cards.compactMap { card in
            guard let id = card.lift.exerciseId, let current = card.lift.currentKg, current > 0 else { return nil }
            let target = LiftTarget(name: card.lift.exerciseKey, currentKg: current, stepKg: card.lift.stepKg,
                                    sets: card.lift.sets, repsTarget: progressionRepsTarget(card.lift.repsTarget))
            let logged = card.sets.map { LoggedSet(exerciseName: $0.exerciseKey, category: nil, setNumber: $0.setIndex, reps: $0.reps, weightKg: $0.weightKg) }
            guard case .due(let next) = Progression.evaluate(target: target, lastSession: logged, autoSuggest: true), next > 0 else { return nil }
            return StrengthAdvance(exerciseId: id, currentWeightKg: next)
        }
    }

    /// W-FIX-P2 RG-26: false once this screen's session is complete (the Log-set button disables).
    public var canLogSet: Bool { session?.isComplete != true }

    public var canComplete: Bool { session != nil && session?.isComplete == false && cards.contains { !$0.sets.isEmpty } }

    public func complete() async {
        guard let session, canComplete else { return }
        let endedAt = now().ISO8601Format()
        let advance = advanceList()
        do { try store.complete(sessionClientId: session.clientId, endedAt: endedAt) } catch { self.error = "Could not complete on this phone."; return }
        queue?.enqueue(.complete(session: session.clientId, StrengthSessionComplete(endedAt: endedAt, advance: advance)))
        self.session = try? store.session(clientId: session.clientId)
        completedAdvance = advance
        timer = timer.stopped()
        await reminderTask?.value   // a set's nudge lands before it is dropped
        await reminders?.sessionEnded(date: session.date)
        refreshPending()
        await sync()
    }

    // MARK: plates

    public func plates(for totalKg: Double?) -> [Double]? {
        guard let totalKg else { return nil }
        return PlateMath.perSide(totalKg: totalKg, barKg: plates.barKg, pairs: plates.pairs)
    }

    /// F-3c: the plates for `kg` as THIS lift is loaded — a dumbbell is per hand, no bar.
    public func plates(for kg: Double?, exerciseKey: String) -> [Double]? {
        guard let kg else { return nil }
        switch StrengthLoad.of(exerciseKey) {
        case .barbell: return plates(for: kg)
        case .dumbbell: return PlateMath.perSideDumbbell(perHandKg: kg, pairs: plates.pairs)
        }
    }

    public func savePlates(_ inventory: PlateInventory) {
        guard inventory.barKg > 0, !inventory.pairs.isEmpty else { return }
        plates = inventory
        try? prefs?.set(PlateInventory.prefKey, inventory)
    }

    // MARK: sync

    public func sync() async {
        guard let queue else { refreshPending(); return }
        let results = await queue.drainOnce()
        refreshPending()
        if results.values.contains(where: { if case .queued = $0 { true } else { false } }) {
            // W-FIX-P3 RG-69: friendly copy only — the raw system error stays out of the note.
            syncNote = pendingCount > 0 ? strengthQueuedSyncNote(pending: pendingCount) : nil
        } else if let refused = results.values.compactMap({ if case .refused(let m) = $0 { m } else { nil } }).first {
            syncNote = "The hub refused a change: \(refused)"
        } else {
            syncNote = pendingCount > 0 ? "\(pendingCount) change\(pendingCount == 1 ? "" : "s") waiting to send." : nil
        }
    }

    // MARK: helpers

    /// nil (with `error` set) when the session row could not be saved — never swallowed (B-117).
    private func ensureSession() -> StrengthSessionLog? {
        if let session, !session.isComplete { return session }
        let s = StrengthSessionLog(sessionId: sessionId, sessionName: sessionName, date: today(), startedAt: now().ISO8601Format())
        do { try store.startSession(s) } catch {
            self.error = "Could not start the session on this phone. Try again."
            return nil
        }
        queue?.enqueue(.createSession(StrengthSessionCreate(clientId: s.clientId, date: s.date, startedAt: s.startedAt, sessionId: sessionId)))
        session = s
        return s
    }

    private func reloadSets() {
        let all = session.flatMap { try? store.sets(sessionClientId: $0.clientId) } ?? []
        for i in cards.indices {
            cards[i].sets = all.filter { $0.exerciseKey == cards[i].lift.exerciseKey }
        }
        recomputeDefaults()
    }

    private func recomputeDefaults() {
        for i in cards.indices {
            let lift = cards[i].lift
            func logged(_ s: [StrengthSetLog]) -> [LoggedSet] {
                s.map { LoggedSet(exerciseName: $0.exerciseKey, category: nil, setNumber: $0.setIndex, reps: $0.reps, weightKg: $0.weightKg) }
            }
            cards[i].defaults = LastSetDefaults.resolve(sessionSets: logged(cards[i].sets), planKg: lift.nextKg ?? lift.currentKg,
                                                        planReps: progressionRepsTarget(lift.repsTarget), lastSessionSets: logged(cards[i].lastTime))
        }
    }

    private func afterWrite() {
        refreshPending()
        Task { await sync() }
    }

    /// F-3a: an empty queue has nothing pending — the note goes, whoever drained it.
    private func refreshPending() {
        pendingCount = queue?.pendingCount ?? 0
        if pendingCount == 0, syncNote?.hasPrefix("The hub refused") != true { syncNote = nil }
    }

    private static func kg(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }

    static func body(_ s: StrengthSetLog) -> StrengthSetIn {
        StrengthSetIn(clientId: s.clientId, exerciseKey: s.exerciseKey, exerciseId: s.exerciseId, setIndex: s.setIndex,
                      kind: s.kind.rawValue, reps: s.reps, weightKg: s.weightKg, durationS: s.durationS, rpe: s.rpe, performedAt: s.performedAt)
    }
}

/// What the app hands the Training screen so it can open the logger and History (nil = previews /
/// tests / no on-disk store → the "Log sets" entry is hidden).
public nonisolated struct StrengthLogDeps: Sendable {
    public let db: AppDatabase
    public let provider: (any TrainingProviding)?
    public let prefs: PrefStore?
    /// B-43 P2: the app's training nudges (nil = none, previews / tests).
    public let reminders: (any WorkoutSessionReminding)?
    public init(db: AppDatabase, provider: (any TrainingProviding)?, prefs: PrefStore?, reminders: (any WorkoutSessionReminding)? = nil) {
        self.db = db; self.provider = provider; self.prefs = prefs; self.reminders = reminders
    }
}

public extension EnvironmentValues {
    @Entry var strengthLogDeps: StrengthLogDeps? = nil
}

/// W-FIX-P3 RG-69: the logger's offline note — no raw "(Could not connect to the server.)".
public nonisolated func strengthQueuedSyncNote(pending: Int) -> String {
    "\(pending) change\(pending == 1 ? "" : "s") saved on this phone — will send when the hub is reachable."
}
