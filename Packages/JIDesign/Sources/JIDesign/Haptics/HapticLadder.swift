import Foundation

// W8-L1 (P-haptics). The intensity ladder: RN `haptics.ts`'s `intensityCurve` (Stevens's power
// law) + `nativeHaptics.ts`'s 5-rung dispatch ladder (`HapticPath`, `HapticCapabilities`, the
// "which rung fires" rule the Android module applies) + `HapticIntensitySlider.tsx`'s pure
// domain helpers (detents, clamp, offset → pct). Pure math: `nonisolated`.

/// Power-law correction for vibrotactile perception (Stevens's power law; docs/research/
/// haptics-android-design.md §8d cites exponents near 0.6 at ~250 Hz, the band most phone LRA
/// motors vibrate in). CONVENTION, tunable — sits inside the research doc's 1.5–2 range.
public nonisolated let jiHapticIntensityCurveK = 1.7

public nonisolated enum JIHapticLadder {
    /// `intensityCurve(pct)` — `pow(pct / 100, 1.7)`. 100 → exactly 1.0 (so the default changes
    /// nobody's felt experience); 1 → small-but-nonzero, never literal 0.
    public static func intensityScale(pct: Int) -> Double {
        pow(Double(pct) / 100, jiHapticIntensityCurveK)
    }

    /// One pulse's final Core Haptics intensity: recipe intensity × scale, clamped to [0, 1].
    public static func scaledIntensity(_ intensity: Double, scale: Double) -> Double {
        min(1, max(0, intensity * scale))
    }
}

// MARK: - The 5-rung dispatch ladder (`nativeHaptics.ts` §2c/§2e, iOS reading)

/// `HapticPath` — which rung actually fired. On Android: constant → composition → predefined →
/// oneshot → fallback. On iOS the first four collapse onto Core Haptics (`.composition`, one
/// `CHHapticPattern` per recipe); `.fallback` is the stock `UIFeedbackGenerator` family.
public nonisolated enum JIHapticPath: String, Sendable, Equatable, CaseIterable {
    case constant, composition, predefined, oneshot, fallback

    /// `normalizePath` — an unrecognized path string reads as "fallback", never an invalid case.
    public init(normalizing raw: String?) {
        self = raw.flatMap(JIHapticPath.init(rawValue:)) ?? .fallback
    }
}

/// `HapticFireResult` — `fired: false` means every native rung declined and the caller runs
/// the recipe's own fallback.
public nonisolated struct JIHapticFireResult: Sendable, Equatable {
    public var fired: Bool
    public var path: JIHapticPath
    public init(fired: Bool, path: JIHapticPath) { self.fired = fired; self.path = path }

    /// What `playHaptic` resolves to when the native engine is absent, declines, or throws.
    public static let declined = JIHapticFireResult(fired: false, path: .fallback)
}

/// `HapticCapabilities` — what the device's haptic hardware confirms. `nil` (no engine at all:
/// Mac, Simulator, a device whose engine failed to start) short-circuits to the fallback rung
/// SYNCHRONOUSLY, exactly as RN's `getHapticCapabilities() === null` branch.
public nonisolated struct JIHapticCapabilities: Sendable, Equatable {
    /// Android `hasVibrator` / iOS `CHHapticEngine.capabilitiesForHardware().supportsHaptics`.
    public var hasVibrator: Bool
    /// Android `hasAmplitudeControl` — Core Haptics always has per-event intensity.
    public var hasAmplitudeControl: Bool
    /// Android's confirmed `PRIMITIVE_*` subset; empty ≠ "no vibrator" (see `hasVibrator`).
    public var primitivesSupported: [String]
    /// Android API level; iOS reports the major OS version.
    public var apiLevel: Int

    public init(hasVibrator: Bool, hasAmplitudeControl: Bool, primitivesSupported: [String], apiLevel: Int) {
        self.hasVibrator = hasVibrator
        self.hasAmplitudeControl = hasAmplitudeControl
        self.primitivesSupported = primitivesSupported
        self.apiLevel = apiLevel
    }

    /// The rung the native module would pick for a recipe on this hardware (`nativeHaptics.test.
    /// ts`'s rung table, iOS reading): no vibrator → nothing fires natively (`.fallback`);
    /// amplitude control or any confirmed primitive → the composition rung; a bare vibrator with
    /// no amplitude control → the predefined rung (stock effects only).
    public func rung(for recipe: JIHapticRecipe) -> JIHapticPath {
        if !hasVibrator { return .fallback }
        if hasAmplitudeControl || !primitivesSupported.isEmpty { return recipe.pulses.isEmpty ? .constant : .composition }
        return .predefined
    }

    /// `settings.tsx` `hapticsCaption` — the one place a device's capability maps onto the
    /// Settings copy. `nil` caps (no native module / engine) → "Basic vibration".
    public static func caption(_ caps: JIHapticCapabilities?) -> String {
        guard let caps else { return "Basic vibration" }
        if !caps.hasVibrator { return "No vibrator" }
        if caps.hasAmplitudeControl || !caps.primitivesSupported.isEmpty { return "Rich haptics" }
        return "Basic vibration"
    }
}

// MARK: - Intensity slider domain (`HapticIntensitySlider.tsx`)

public nonisolated enum JIHapticIntensity {
    public static let min = 1
    public static let max = 100
    /// 5 detents (decision of record): not the impossible 0, not a dense 10-step grid.
    public static let detents = [20, 40, 60, 80, 100]
    /// One detent-sized nudge per accessibility increment/decrement.
    public static let step = 20

    /// `clampIntensityPct` — the SLIDER's clamp: non-finite → the minimum (a not-yet-measured
    /// track reads as 1), else rounded into [1, 100].
    public static func clampPct(_ n: Double) -> Int {
        guard n.isFinite else { return min }
        return Swift.min(max, Swift.max(min, Int(n.rounded())))
    }

    /// `detentBucketForPct` — index (0–4) of the detent nearest `pct`, ties toward the lower detent.
    public static func detentBucket(forPct pct: Int) -> Int {
        var bestIdx = 0
        var bestDist = Int.max
        for (i, d) in detents.enumerated() {
            let dist = abs(d - pct)
            if dist < bestDist { bestDist = dist; bestIdx = i }
        }
        return bestIdx
    }

    /// `pctFromOffsetX` — continuous (non-snapping) touch-x → percent; `trackWidth <= 0` (no
    /// layout yet) reads as the minimum.
    public static func pct(fromOffsetX x: Double, trackWidth: Double) -> Int {
        guard trackWidth > 0 else { return min }
        return clampPct((x / trackWidth) * Double(max))
    }
}
