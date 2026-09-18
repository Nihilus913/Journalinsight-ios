import SwiftUI
import JICore

/// The interactions that carry a haptic. One case per ladder rung — adding a new
/// interaction means adding a case here, not a new ad-hoc `.sensoryFeedback` call
/// at the call site.
public enum JIHapticEvent: Sendable, Equatable, CaseIterable {
    case pressIn
    case toggleOn
    case toggleOff
    case success
    case warning
}

/// The haptic ladder: maps each `JIHapticEvent` to the feedback it fires.
///
/// Scaffolded so Q#2 (spec §11.2 / DESIGN-5 — keep the four custom Android
/// `CHHapticPattern` recipes vs simplify to stock `.sensoryFeedback` cases) is a
/// **one-file swap**: everything that wants a haptic calls `JIHaptic.feedback(for:)`
/// and never touches `SensoryFeedback` or `CHHapticEngine` directly. Swapping the
/// engine later means editing the bodies below, not any call site.
public enum JIHaptic {
    /// The stock `SensoryFeedback` currently wired for each event. Swap this
    /// mapping (or replace its use with a `CHHapticPattern` player) to resolve Q#2
    /// without touching any call site.
    public nonisolated static func feedback(for event: JIHapticEvent) -> SensoryFeedback {
        switch event {
        case .pressIn: .selection
        case .toggleOn: .impact(weight: .light)
        case .toggleOff: .impact(weight: .light, intensity: 0.6)
        case .success: .success
        case .warning: .warning
        }
    }
}

/// Fires `event`'s ladder feedback when `trigger` transitions `false -> true` —
/// the shared "only on press-in, not release" gate every haptic-carrying control
/// should use instead of a bespoke `.sensoryFeedback` call.
public struct JIHapticModifier: ViewModifier {
    let event: JIHapticEvent
    let trigger: Bool
    public init(event: JIHapticEvent, trigger: Bool) {
        self.event = event
        self.trigger = trigger
    }
    public func body(content: Content) -> some View {
        content.sensoryFeedback(JIHaptic.feedback(for: event), trigger: trigger) { old, new in new && !old }
    }
}

public extension View {
    /// Routes a boolean press/toggle trigger through the `JIHaptic` ladder for `event`,
    /// firing only on the `false -> true` edge (press-in, never release).
    func jiHaptic(_ event: JIHapticEvent, trigger: Bool) -> some View {
        modifier(JIHapticModifier(event: event, trigger: trigger))
    }
}

// MARK: - W8-L1 (P-haptics): the RN vocabulary — `fire(recipe)`, engine + fallback, prefs gate
//
// Port of `haptics.ts`'s internal `fire()` and the `hapticXxx()` exports. Everything above this
// line (JIHapticEvent / feedback(for:) / jiHaptic) is the W1 press-in ladder and stays as-is;
// the vocabulary below is what the RN call sites (VerdictHero, GateRespondCard, SyncButton,
// DayStrip, DraggableTodayTiles, LiftSteppers, SessionCoach) name. Gate order, unchanged:
//   1. prefs.enabled — the master switch, first; off = no marker, no engine call, no fallback.
//   2. the [FEELGATE_HAPTIC] marker, before any native call.
//   3. capabilities decide the branch SYNCHRONOUSLY: engine present → `player.play(recipe,
//      scale)`, falling through to the recipe's own fallback when it declined (`fired: false`)
//      or threw; engine absent (Mac, Simulator, a failed engine) → the fallback directly.

/// `playHaptic(recipe, scale)` — the native engine seam. `capabilities == nil` means "no
/// engine" and the dispatcher never calls `play`. MainActor: `CHHapticEngine` is not Sendable
/// and every call site is a SwiftUI view.
public protocol JIHapticPlayer: AnyObject {
    var capabilities: JIHapticCapabilities? { get }
    func play(_ recipe: JIHapticRecipe, scale: Double) throws -> JIHapticFireResult
}

/// The rung-5 fallback seam (`UIFeedbackGenerator` family on iOS; a no-op elsewhere).
public protocol JIHapticFallbackPlayer: AnyObject {
    /// Plays ONE atomic pulse — `.double` is expanded by the dispatcher into two gapped calls.
    func play(_ fallback: JIHapticFallback)
}

/// The one internal fire point every vocabulary cue routes through (`haptics.ts` `fire`).
/// `prefs` is the RN module-level cache (`isHapticsEnabledSync` / `isHapticsIntensitySync`):
/// defaults OPEN (enabled, 100) until `HapticsPrefsStore.warm(from:)` (JIFeatures) loads the
/// persisted values — missing a handful of early haptics on a cold start is harmless.
public final class JIHapticDispatcher {
    public static let shared = JIHapticDispatcher()

    /// The synchronous prefs cache. Set by `HapticsPrefsStore` (JIFeatures) on load and on every
    /// Settings change — BEFORE the disk write resolves, exactly as RN.
    public var prefs: JIHapticsPrefs = .default
    public var player: (any JIHapticPlayer)?
    public var fallback: any JIHapticFallbackPlayer
    /// Epoch ms for the marker (injectable for tests).
    public var nowMs: () -> Int64 = JIFeelgateMarker.nowMs
    /// Where `[FEELGATE_HAPTIC]` lines go (unified log by default; tests capture).
    public var marker: JIFeelgateMarker.Sink = JIFeelgateMarker.unifiedLogSink
    /// Verdict-reveal dedupe: the last verdict key the reveal haptic fired for (RN
    /// `verdictRevealed(prev, next)` over the persisted snapshot; in-process here).
    public private(set) var lastRevealKey: String?

    public init(player: (any JIHapticPlayer)? = nil, fallback: (any JIHapticFallbackPlayer)? = nil) {
        self.player = player ?? JIHapticDispatcher.defaultPlayer()
        self.fallback = fallback ?? JIHapticDispatcher.defaultFallback()
    }

    /// `fire(recipeName)`.
    public func fire(recipe name: JIHapticRecipeName) {
        guard prefs.enabled else { return }
        let recipe = JIHapticRecipes.recipe(name)
        JIFeelgateMarker.log(label: recipe.label, timestampMs: nowMs(), to: marker)
        let scale = JIHapticLadder.intensityScale(pct: prefs.intensity)
        if let player, player.capabilities != nil {
            let result = (try? player.play(recipe, scale: scale)) ?? .declined
            if result.fired { return }
        }
        playFallback(recipe.fallback)
    }

    /// The `hapticXxx()` exports: resolves the cue's recipe (nil = fires nothing) and fires.
    public func fire(_ cue: JIHapticCue) {
        guard let name = cue.recipeName else { return }
        fire(recipe: name)
    }

    /// `hapticVerdictReveal(tone)` gated by `verdictRevealed(prev, next)`: fires once per
    /// distinct verdict `key` (a same-day refetch or a tab return re-presents the same key and
    /// stays silent). `nil` key = ungated.
    public func fireVerdictReveal(_ tone: VerdictTone, key: String?) {
        if let key {
            guard key != lastRevealKey else { return }
            lastRevealKey = key
        }
        fire(.verdictReveal(tone))
    }

    /// Test-only: `__resetHapticsPrefsForTests` + the reveal dedupe.
    public func resetForTests() {
        prefs = .default
        lastRevealKey = nil
    }

    private func playFallback(_ fallback: JIHapticFallback) {
        switch fallback {
        case .double(let pulse, let gapMs):
            // RN's fallback closure: two gapped calls, the marker logged once up front.
            self.fallback.play(pulse)
            let second = self.fallback
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(gapMs))
                second.play(pulse)
            }
        default:
            self.fallback.play(fallback)
        }
    }
}

public extension JIHaptic {
    /// `hapticPressIn()` / `hapticSelection()` / … — fire a vocabulary cue through the shared
    /// dispatcher (prefs gate → marker → engine or fallback).
    static func fire(_ cue: JIHapticCue) { JIHapticDispatcher.shared.fire(cue) }
    /// `hapticGateChange(tier)`.
    static func fireGateChange(_ tier: JIGateChangeTier) { JIHapticDispatcher.shared.fire(.gateChange(tier)) }
}

/// Fires `cue` when `value` changes (never on first appearance) and `when(newValue)` holds — the
/// "genuine selection edge" gate every RN call site applies (`if (!selected) hapticSelection()`,
/// the live-drag swap, the drop commit).
public struct JIHapticCueModifier<Value: Equatable>: ViewModifier {
    let cue: JIHapticCue
    let value: Value
    let when: (Value) -> Bool
    public init(cue: JIHapticCue, value: Value, when: @escaping (Value) -> Bool) {
        self.cue = cue; self.value = value; self.when = when
    }
    public func body(content: Content) -> some View {
        content.onChange(of: value) { _, new in if when(new) { JIHaptic.fire(cue) } }
    }
}

public extension View {
    /// Fires `cue` on every change of `value` for which `when(newValue)` is true.
    func jiHapticCue<V: Equatable>(_ cue: JIHapticCue, on value: V, when: @escaping (V) -> Bool = { _ in true }) -> some View {
        modifier(JIHapticCueModifier(cue: cue, value: value, when: when))
    }
    /// Fires `cue` on `trigger`'s `false -> true` edge only.
    func jiHapticCue(_ cue: JIHapticCue, trigger: Bool) -> some View {
        modifier(JIHapticCueModifier(cue: cue, value: trigger, when: { $0 }))
    }
    /// `hapticVerdictReveal(tone)` on `trigger`'s rising edge, once per distinct `key` (the
    /// verdict-CHANGE signal, not an every-open one).
    func jiHapticVerdictReveal(_ tone: VerdictTone, key: String, trigger: Bool) -> some View {
        onChange(of: trigger) { _, new in if new { JIHapticDispatcher.shared.fireVerdictReveal(tone, key: key) } }
    }
}

// MARK: - Default players

#if canImport(CoreHaptics)
import CoreHaptics

/// Core Haptics rendering of the recipe table: one `CHHapticPattern` per fire, every event's
/// intensity = recipe intensity × the resolved scale. `capabilities == nil` when the hardware
/// has no haptics (Mac, Simulator) or the engine failed to start — the dispatcher then takes
/// the fallback rung synchronously.
public final class JICoreHapticsPlayer: JIHapticPlayer {
    private var engine: CHHapticEngine?
    private var startFailed = false
    public init() {}

    public var capabilities: JIHapticCapabilities? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, !startFailed else { return nil }
        return JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: true, primitivesSupported: ["TICK", "CLICK", "THUD", "QUICK_RISE", "SLOW_RISE"],
                                    apiLevel: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    private func runningEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let e = try CHHapticEngine()
        e.resetHandler = { [weak self] in try? self?.engine?.start() }
        e.stoppedHandler = { [weak self] _ in Task { @MainActor [weak self] in self?.engine = nil } }
        try e.start()
        engine = e
        return e
    }

    public func play(_ recipe: JIHapticRecipe, scale: Double) throws -> JIHapticFireResult {
        guard !recipe.pulses.isEmpty else { return .declined }
        do {
            let engine = try runningEngine()
            let events = recipe.pulses.map { pulse -> CHHapticEvent in
                let params = [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(JIHapticLadder.scaledIntensity(pulse.intensity, scale: scale))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(pulse.sharpness)),
                ]
                let at = TimeInterval(pulse.atMs) / 1000
                if let ms = pulse.durationMs {
                    return CHHapticEvent(eventType: .hapticContinuous, parameters: params, relativeTime: at, duration: TimeInterval(ms) / 1000)
                }
                return CHHapticEvent(eventType: .hapticTransient, parameters: params, relativeTime: at)
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return JIHapticFireResult(fired: true, path: .composition)
        } catch {
            startFailed = engine == nil
            return .declined
        }
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// The stock `UIFeedbackGenerator` family — RN's expo-haptics fallback, one-to-one.
public final class JIUIKitFallbackPlayer: JIHapticFallbackPlayer {
    public init() {}
    public func play(_ fallback: JIHapticFallback) {
        switch fallback {
        case .impact(let w):
            let style: UIImpactFeedbackGenerator.FeedbackStyle = switch w {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            case .soft: .soft
            case .rigid: .rigid
            }
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case .notification(let k):
            let type: UINotificationFeedbackGenerator.FeedbackType = switch k {
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
            UINotificationFeedbackGenerator().notificationOccurred(type)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .double(let inner, _):
            play(inner)
        }
    }
}
#endif

/// No-op fallback (Mac / watchOS test hosts).
public final class JINoopHapticFallbackPlayer: JIHapticFallbackPlayer {
    public init() {}
    public func play(_ fallback: JIHapticFallback) {}
}

extension JIHapticDispatcher {
    static func defaultPlayer() -> (any JIHapticPlayer)? {
        #if canImport(CoreHaptics)
        return JICoreHapticsPlayer()
        #else
        return nil
        #endif
    }
    static func defaultFallback() -> any JIHapticFallbackPlayer {
        #if canImport(UIKit) && !os(watchOS)
        return JIUIKitFallbackPlayer()
        #else
        return JINoopHapticFallbackPlayer()
        #endif
    }
}
