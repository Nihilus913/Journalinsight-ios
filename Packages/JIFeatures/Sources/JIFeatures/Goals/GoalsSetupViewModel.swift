import Foundation
import Observation
import JICore
import JICompute
import JIPersistence

/// B-57 W1: one read-only "Next working weight" row. `kg == nil` renders "— No data", never 0.
public nonisolated struct NextWorkingWeight: Equatable, Sendable { public let name: String; public let kg: Double? }

/// B-57 W1: GoalsSetup's two strength rows, read from the local `strength_state` mirror.
/// W-FIX1 BUG-11: the board labels ("Bench press", "Bent-over row") match the hub's plan names
/// ("Barbell Bench Press", "Barbell Row") by their movement words, not by exact string. The plan
/// repeats a lift per session; the most recently updated row wins (the heavier on a tie).
public nonisolated func nextWorkingWeights(entries: [StrengthStateEntry]) -> [NextWorkingWeight] {
    let rows: [(name: String, matches: (String) -> Bool)] = [
        ("Bench press", { $0.contains("bench press") && !$0.contains("incline") && !$0.contains("db ") && !$0.contains("dumbbell") }),
        ("Bent-over row", { $0 == "bent-over row" || $0 == "barbell row" || $0 == "bent over row" || $0 == "barbell bent-over row" || $0 == "barbell bent over row" }),
    ]
    return rows.map { row in
        let hits = entries.filter { row.matches($0.exerciseName.lowercased()) }
        let pick = hits.max { a, b in
            a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.currentWeightKg < b.currentWeightKg
        }
        return NextWorkingWeight(name: row.name, kg: pick?.currentWeightKg)
    }
}

/// B-73: what `saveNutrition` did. `.needsDeficitCheck` = nothing was written; the view asks
/// "Does your goal already include a deficit?" and calls again with `confirmed: true`.
public enum NutritionSaveOutcome: Equatable, Sendable { case saved, needsDeficitCheck, failed }

/// W4-L3 (P-goals), mirrors `mobile/app/goals-setup.tsx` + `mobile/src/data/useGoals.ts`'s
/// `useGoals`/`useUpdateGoals`. Reads through the frozen `EnergyProviding.goals()` (the same
/// `GET /planning/goals` route the Energy tab already calls); writes through the new
/// `GoalsProviding.updateGoals` (`PUT /planning/goals`). On a successful save, the result is also
/// written into `GoalStore`'s `goal_targets_mirror` (local-first mirror, R6c-3a) so it never
/// drifts stale relative to what was actually shown/edited.
@Observable @MainActor
public final class GoalsSetupViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, saving, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var goals: Goals?
    public private(set) var savedAt: Date?

    /// B-73: the stored nutrition goals (`.unset` until the user saves some; never a default).
    /// The phone's `PrefStore` (`goals.macros`) is the source of truth, not the hub document.
    public private(set) var macroGoals: MacroGoals?
    /// The 7-day Health burn (nil when Health has nothing). Only used for the implied-deficit line,
    /// the settle note and the sanity prompt; the band itself needs no Health.
    public private(set) var burnWindow: EnergyBurnWindow?
    /// True after a nutrition save whose hub mirror is still queued (offline).
    public private(set) var hubPending = false

    private let provider: any GoalsSetupProviding
    private let goalStore: GoalStore?
    private let now: () -> Date
    private let strengthStore: StrengthStateStore
    private let macroStore: MacroGoalsStore?
    private let mirror: GoalsMirror?   // TEMP bridge until B-50: hub weekly gate
    private let burnSource: (@MainActor () async -> EnergyBurnWindow?)?
    private let onNutritionSaved: (@MainActor () -> Void)?

    public init(
        provider: any GoalsSetupProviding, goalStore: GoalStore? = nil, now: @escaping () -> Date = Date.init,
        strengthStore: StrengthStateStore = StrengthStateStore(),
        macroStore: MacroGoalsStore? = nil, mirror: GoalsMirror? = nil,
        burnSource: (@MainActor () async -> EnergyBurnWindow?)? = nil,
        onNutritionSaved: (@MainActor () -> Void)? = nil
    ) {
        self.provider = provider
        self.goalStore = goalStore
        self.now = now
        self.strengthStore = strengthStore
        self.macroStore = macroStore
        self.mirror = mirror
        self.burnSource = burnSource
        self.onNutritionSaved = onNutritionSaved
    }

    /// B-57 W1: read-only; updates itself after each logged session.
    public var nextWorkingWeights: [NextWorkingWeight] {
        _ = strengthRevision
        return JIFeatures.nextWorkingWeights(entries: strengthStore.entries())
    }

    public func load() async {
        // B-73: local first, so the nutrition section never waits on the hub. `load()` never pushes
        // (Review Focus 4: the only PUT is `saveNutrition`'s mirror on a user save).
        macroGoals = try? macroStore?.load()
        burnWindow = await burnSource?()
        phase = .loading
        do {
            let result = try await provider.goals()
            goals = result
            await refreshStrengthState()
            phase = .loaded
        } catch {
            phase = .error(Self.describe(error))
        }
    }

    /// W-FIX1 BUG-11: the hub is the source of `strength_state`; pull it into the local mirror so
    /// the rows show the hub's weights (and keep them offline). A failure keeps the mirror as is.
    private func refreshStrengthState() async {
        guard let training = provider as? any TrainingProviding,
              let rows = try? await training.exercises() else { return }
        strengthStore.mirrorHub(rows, now: now())
        strengthRevision += 1
    }

    /// Bumps when the mirror is refreshed, so `nextWorkingWeights` re-renders.
    private var strengthRevision = 0

    /// Applies `patch` via `PUT /planning/goals`; on success the server's full document replaces
    /// `goals` (never the local optimistic merge — same "server is source of truth" rule as the
    /// RN oracle's `onSuccess`) and is upserted into `goal_targets_mirror`.
    @discardableResult
    public func save(_ patch: GoalsUpdate) async -> Bool {
        savedAt = nil
        phase = .saving
        do {
            let result = try await provider.updateGoals(patch)
            goals = result
            try? goalStore?.saveGoalTargetsMirror(result, now: now())
            savedAt = now()
            phase = .loaded
            return true
        } catch {
            phase = .error(Self.describe(error))
            return false
        }
    }

    /// "The band settles after a full week of Apple Health data." shows while this is false.
    public var bandSettled: Bool { burnWindow?.settled ?? false }

    /// The plan band for a pending edit: the user's target ± 100 (nil while no valid kcal goal).
    public func bandPreview(for goals: MacroGoals) -> (low: Int, high: Int)? {
        guard let k = goals.kcal, k.isValid else { return nil }
        return EnergyBand.band(targetKcal: Int(k.targetKcal.rounded()))
    }

    /// "≈ 480 kcal under what you burn" — information only; nil without a burn or a goal.
    public func impliedDeficitText(for goals: MacroGoals) -> String? {
        guard let k = goals.kcal, k.isValid, let burn = burnWindow?.burnKcal else { return nil }
        return EnergyBand.impliedDeficitText(EnergyBand.impliedDeficit(burnKcal: burn, targetKcal: Int(k.targetKcal.rounded())))
    }

    /// Only for "subtract a deficit" goals, and only when Health knows the burn.
    public func needsDeficitCheck(_ goals: MacroGoals) -> Bool {
        guard let k = goals.kcal, case .subtractDeficit(let mode) = k.basis else { return false }
        return EnergyBand.shouldAskIfGoalIncludesDeficit(goalKcal: k.goalKcal, deficitKcal: mode.kcalPerDay,
                                                         burnKcal: burnWindow?.burnKcal)
    }

    /// B-73: saves on the phone first (the source of truth), then pushes the temporary hub mirror.
    /// `.needsDeficitCheck` writes nothing. `hubPending` says whether the mirror is still queued.
    @discardableResult
    public func saveNutrition(_ edited: MacroGoals, confirmed: Bool = false) async -> NutritionSaveOutcome {
        guard let macroStore else { return .failed }
        if !confirmed && needsDeficitCheck(edited) { return .needsDeficitCheck }
        do { try macroStore.save(edited) } catch { phase = .error("Couldn't save on this phone — try again."); return .failed }
        macroGoals = edited
        savedAt = now()
        onNutritionSaved?()
        // TEMP bridge until B-50: hub weekly gate
        guard let mirror else { hubPending = false; return .saved }
        switch await mirror.push(edited) {
        case .delivered(let server):
            hubPending = false
            // fixer2 RF3-STATUS: the hub took the PUT, so a load-time "Hub offline" is stale. Only a
            // load error is cleared (no hub document yet) — a failed weight/strength save stays.
            let loadFailed = goals == nil
            if let server {
                goals = server
                try? goalStore?.saveGoalTargetsMirror(server, now: now())
            } else if loadFailed {
                goals = try? await provider.goals()
            }
            if loadFailed, case .error = phase { phase = .loaded }
        case .queued:
            hubPending = true
        case .nothingToSend:
            hubPending = false
        }
        return .saved
    }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}
