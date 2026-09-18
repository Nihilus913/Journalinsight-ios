import Foundation
import SwiftUI
import JICore

// W8-L1 (P-haptics). Port of `mobile/src/haptics/haptics.ts`'s recipe table + the pure
// classifiers (`gateChangeTierFromTones`, `gateChangeTierFromHrCap`, the verdict-tone → recipe
// map). Every haptic the app fires names ONE row of `JIHapticRecipes.table` — the one place a
// pulse's timings live (CONTEXT-GUI-POLISH §4.4's "no ad-hoc haptic durations outside the recipe
// table"). Pure values: `nonisolated` (JIDesign is MainActor-default).

/// `HapticRecipeName` — the 11 vocabulary moments. Raw values are the RN labels byte-for-byte:
/// they are what `[FEELGATE_HAPTIC] <label>` prints, and `feelgate.py` filters by exact label.
public nonisolated enum JIHapticRecipeName: String, Sendable, Equatable, Hashable, CaseIterable {
    case pressIn
    case selection
    case saveSuccess
    case goalHit
    case verdictRevealGo = "verdictReveal:go"
    case verdictRevealAmber = "verdictReveal:amber"
    case verdictRevealRed = "verdictReveal:red"
    case dragDrop
    case gateChangeRoutine = "gateChange:routine"
    case gateChangeChanged = "gateChange:changed"
    case gateChangeFailed = "gateChange:failed"

    /// `HAPTIC_RECIPES[name].label` — always equal to the key itself.
    public var label: String { rawValue }
}

/// One Core Haptics event of a recipe (the iOS rendering of RN's `primitives`/`oneshot` rungs).
/// `intensity` is PRE-scale — the player multiplies it by the resolved intensity-curve scale at
/// dispatch (never pre-multiplied here), exactly as the Android module multiplies `scale`.
public nonisolated struct JIHapticPulse: Sendable, Equatable {
    /// 0–1, before the intensity scale is applied.
    public var intensity: Double
    /// 0–1 Core Haptics sharpness (0 = dull thud, 1 = crisp tick).
    public var sharpness: Double
    /// Offset from the recipe's start, in ms.
    public var atMs: Int
    /// nil = a transient (tap); a value = a continuous event of that length.
    public var durationMs: Int?

    public init(intensity: Double, sharpness: Double, atMs: Int = 0, durationMs: Int? = nil) {
        self.intensity = intensity
        self.sharpness = sharpness
        self.atMs = atMs
        self.durationMs = durationMs
    }
}

/// `UIImpactFeedbackGenerator.FeedbackStyle` / `SensoryFeedback` impact rungs, as data.
public nonisolated enum JIImpactWeight: Sendable, Equatable { case light, medium, heavy, soft, rigid }
/// `UINotificationFeedbackGenerator.FeedbackType` / `SensoryFeedback` notification rungs.
public nonisolated enum JINotificationKind: Sendable, Equatable { case success, warning, error }

/// The rung-5 fallback (RN: the exact expo-haptics call each recipe makes when the native
/// module is absent) — the stock system generator to use when Core Haptics is unavailable
/// (no engine, Mac, an engine that failed to start). `.double` is the ONLY multi-pulse fallback
/// (gateChange:changed), kept as two gapped calls exactly as RN's fallback closure.
public nonisolated indirect enum JIHapticFallback: Sendable, Equatable {
    case impact(JIImpactWeight)
    case notification(JINotificationKind)
    case selection
    case double(JIHapticFallback, gapMs: Int)

    /// The declarative `SensoryFeedback` for this fallback (for `.sensoryFeedback`-style call
    /// sites); `.double` collapses to its single pulse — SwiftUI cannot express a gap.
    public var sensoryFeedback: SensoryFeedback {
        switch self {
        case .impact(.light): .impact(weight: .light)
        case .impact(.medium): .impact(weight: .medium)
        case .impact(.heavy): .impact(weight: .heavy)
        case .impact(.soft): .impact(flexibility: .soft)
        case .impact(.rigid): .impact(flexibility: .rigid)
        case .notification(.success): .success
        case .notification(.warning): .warning
        case .notification(.error): .error
        case .selection: .selection
        case .double(let inner, _): inner.sensoryFeedback
        }
    }
}

/// `HapticRecipe` — the documented spec both the Core Haptics player (rung "composition"/
/// "oneshot" → `pulses`) and the fallback path (`fallback`) implement from.
public nonisolated struct JIHapticRecipe: Sendable, Equatable {
    public let name: JIHapticRecipeName
    /// `[FEELGATE_HAPTIC] <label>` — same string as `name.rawValue`.
    public var label: String { name.label }
    /// The Core Haptics rendering. Empty = no composition rung (RN's constant-only recipes still
    /// get one here, since iOS has no `performHapticFeedback` constants).
    public let pulses: [JIHapticPulse]
    public let fallback: JIHapticFallback

    public init(name: JIHapticRecipeName, pulses: [JIHapticPulse], fallback: JIHapticFallback) {
        self.name = name
        self.pulses = pulses
        self.fallback = fallback
    }
}

/// Gap between the "changed" tier's two pulses (RN `DOUBLE_PULSE_GAP_MS`) — long enough to feel
/// like two distinct taps, short enough to still read as one event. The Core Haptics path
/// schedules the same gap inside ONE pattern; the fallback path uses two gapped calls.
public nonisolated let jiHapticDoublePulseGapMs = 110

/// `HAPTIC_RECIPES` — the 11-row table. Pulse shapes follow each RN recipe's `primitives`
/// column (its highest-quality rung: TICK/CLICK = crisp transients, THUD = dull, QUICK/SLOW_RISE
/// = continuous ramps, REJECT = one long low buzz); the `fallback` column mirrors RN's
/// expo-haptics fallback call one-to-one, so the pinned RN tests still describe this table.
public nonisolated enum JIHapticRecipes {
    public static let table: [JIHapticRecipeName: JIHapticRecipe] = {
        var t: [JIHapticRecipeName: JIHapticRecipe] = [:]
        func add(_ name: JIHapticRecipeName, _ pulses: [JIHapticPulse], _ fallback: JIHapticFallback) {
            t[name] = JIHapticRecipe(name: name, pulses: pulses, fallback: fallback)
        }
        // TICK 1.0 · oneshot 12 ms @0.5 · expo impactAsync(Light)
        add(.pressIn, [JIHapticPulse(intensity: 0.5, sharpness: 0.8)], .impact(.light))
        // LOW_TICK 1.0 · oneshot 8 ms @0.35 · expo selectionAsync
        add(.selection, [JIHapticPulse(intensity: 0.35, sharpness: 0.6)], .selection)
        // CLICK 1.0 · oneshot 22 ms @0.75 · expo impactAsync(Light) — byte-identical fallback to
        // pressIn (the E18-3 finding this vocabulary traces to); the two diverge above this rung.
        add(.saveSuccess, [JIHapticPulse(intensity: 0.75, sharpness: 0.5)], .impact(.light))
        // QUICK_RISE 0.8 → THUD 1.0 @+60 ms · expo impactAsync(Heavy) — the single heaviest cue.
        add(.goalHit, [
            JIHapticPulse(intensity: 0.8, sharpness: 0.3, atMs: 0, durationMs: 60),
            JIHapticPulse(intensity: 1.0, sharpness: 0.2, atMs: 60),
        ], .impact(.heavy))
        // TICK 0.7 → CLICK 0.85 @+55 ms · expo notificationAsync(Success)
        add(.verdictRevealGo, [
            JIHapticPulse(intensity: 0.7, sharpness: 0.6, atMs: 0),
            JIHapticPulse(intensity: 0.85, sharpness: 0.7, atMs: 55),
        ], .notification(.success))
        // SLOW_RISE 0.6 (120 ms) → TICK 0.6 @+55 ms after it · expo notificationAsync(Warning)
        add(.verdictRevealAmber, [
            JIHapticPulse(intensity: 0.6, sharpness: 0.3, atMs: 0, durationMs: 120),
            JIHapticPulse(intensity: 0.6, sharpness: 0.8, atMs: 175),
        ], .notification(.warning))
        // REJECT constant — identical recipe to gateChange:failed by design
        // (`gateChangeTierFromTones` classifies any red tone as "failed") · expo Error.
        add(.verdictRevealRed, [JIHapticPulse(intensity: 1.0, sharpness: 0.1, atMs: 0, durationMs: 180)], .notification(.error))
        // GESTURE_END constant · expo performAndroidHapticsAsync(Gesture_End) → medium impact on iOS.
        add(.dragDrop, [JIHapticPulse(intensity: 0.6, sharpness: 0.4)], .impact(.medium))
        // SEGMENT_FREQUENT_TICK constant · expo Segment_Frequent_Tick → one light, soft tap.
        add(.gateChangeRoutine, [JIHapticPulse(intensity: 0.3, sharpness: 0.7)], .impact(.soft))
        // CLICK 0.7 → CLICK 0.7 @+110 ms, ONE atomic pattern · expo: two Clock_Tick calls 110 ms apart.
        add(.gateChangeChanged, [
            JIHapticPulse(intensity: 0.7, sharpness: 0.9, atMs: 0),
            JIHapticPulse(intensity: 0.7, sharpness: 0.9, atMs: jiHapticDoublePulseGapMs),
        ], .double(.impact(.rigid), gapMs: jiHapticDoublePulseGapMs))
        // REJECT constant · expo Reject — the heaviest, most attention-grabbing cue.
        add(.gateChangeFailed, [JIHapticPulse(intensity: 1.0, sharpness: 0.1, atMs: 0, durationMs: 180)], .notification(.error))
        return t
    }()

    /// Total-function lookup — every `JIHapticRecipeName` has a row (asserted in tests).
    public static func recipe(_ name: JIHapticRecipeName) -> JIHapticRecipe {
        guard let r = table[name] else { preconditionFailure("JIHapticRecipes: missing row for \(name.rawValue)") }
        return r
    }
}

// MARK: - The exported vocabulary (RN `hapticXxx()` functions, as data)

/// `GateChangeTier` — three physically distinct severity tiers for a gate-state change.
public nonisolated enum JIGateChangeTier: String, Sendable, Equatable, CaseIterable {
    /// A same-state refresh (a new day, same verdict tone) — one light, soft tap.
    case routine
    /// The state actually moved — a genuine TWO-pulse pattern.
    case changed
    /// An outright failure / safety-cap breach — the heaviest cue in the vocabulary.
    case failed

    public var recipeName: JIHapticRecipeName {
        switch self {
        case .routine: .gateChangeRoutine
        case .changed: .gateChangeChanged
        case .failed: .gateChangeFailed
        }
    }
}

/// `HrCapState` (`mobile/src/lib/hrSafety.ts`) as the haptics layer sees it. JIDesign cannot
/// import JIFeatures' `SessionCoachViewModel.CapState`; the Session Coach call site maps its
/// own enum onto this one case-for-case (same four names).
public nonisolated enum JIHrCapState: String, Sendable, Equatable, CaseIterable {
    case unknown, under, approaching, breach
}

/// The RN `hapticXxx()` exports, as one enum: a call site names the MOMENT, the dispatcher
/// resolves the recipe. `recipeName == nil` means "fires nothing" (verdictReveal("muted")).
public nonisolated enum JIHapticCue: Sendable, Equatable {
    /// `hapticPressIn` — press-IN feedback for the highest-traffic single-tap targets.
    case pressIn
    /// `hapticSelection` — day-strip nav, a stepper tap, pull-to-refresh triggering, a live drag swap.
    case selection
    /// `hapticSaveSuccess` — a log/save that actually saved (GateRespondCard's saved response).
    case saveSuccess
    /// `hapticGoalHit` — a PR hit; reserved for that one moment.
    case goalHit
    /// `hapticVerdictReveal(tone)` — go/amber/red → success/warning/error; muted fires nothing.
    case verdictReveal(VerdictTone)
    /// `hapticDragDrop` — the reorder committing when the finger lifts.
    case dragDrop
    /// `hapticGateChange(tier)`.
    case gateChange(JIGateChangeTier)

    public var recipeName: JIHapticRecipeName? {
        switch self {
        case .pressIn: .pressIn
        case .selection: .selection
        case .saveSuccess: .saveSuccess
        case .goalHit: .goalHit
        case .verdictReveal(let tone): JIHapticRecipes.verdictRevealRecipe(for: tone)
        case .dragDrop: .dragDrop
        case .gateChange(let tier): tier.recipeName
        }
    }
}

public nonisolated extension JIHapticRecipes {
    /// `hapticVerdictReveal`'s tone → recipe map: go/amber/red; "muted" (no verdict yet —
    /// nothing to announce) is nil.
    static func verdictRevealRecipe(for tone: VerdictTone) -> JIHapticRecipeName? {
        switch tone {
        case .go: .verdictRevealGo
        case .amber: .verdictRevealAmber
        case .red: .verdictRevealRed
        case .muted: nil
        }
    }

    /// `gateChangeTierFromTones` — a RED verdict is always "failed" regardless of what it changed
    /// from; a new day at the SAME tone is "routine"; no earlier day (the very first verdict)
    /// reads as "routine"; anything else that changed tone is "changed".
    static func gateChangeTier(prevTone: VerdictTone?, nextTone: VerdictTone) -> JIGateChangeTier {
        if nextTone == .red { return .failed }
        if prevTone == nil || prevTone == nextTone { return .routine }
        return .changed
    }

    /// `gateChangeTierFromHrCap` — nil = "nothing to feel this tick" (no edge, or arriving at /
    /// leaving "unknown"); breaching the cap is always "failed", however reached (even from a
    /// nil/unknown baseline); any other real transition is "changed". Never "routine".
    static func gateChangeTier(prevCap prev: JIHrCapState?, nextCap next: JIHrCapState) -> JIGateChangeTier? {
        if prev == next { return nil }
        if next == .breach { return .failed }
        if prev == nil || prev == .unknown || next == .unknown { return nil }
        return .changed
    }

    /// `verdictRevealed(prev, next)` (`mobile/src/lib/celebrationTriggers.ts`) — the reveal
    /// haptic is a verdict-CHANGE signal, not an every-open one: a same-day refetch wobble or a
    /// tab return must not re-fire. `date == nil` or a muted tone never counts as a reveal.
    static func verdictRevealed(prevDate: String?, hadPrev: Bool, nextDate: String?, nextTone: VerdictTone) -> Bool {
        if nextDate == nil || nextTone == .muted { return false }
        return !hadPrev || prevDate != nextDate
    }
}
