import Foundation

// W8-L1 (P-haptics). Port of `mobile/src/haptics/hapticsPrefs.ts`'s VALUES: the two persisted
// prefs (enabled — the sole master switch; intensity — only ever SCALES an already-permitted
// fire), their keys, defaults and clamp. Persistence itself (RN `getLocalPref`/`setLocalPref`)
// lives in JIFeatures over `PrefStore` (`HapticsPrefsStore`, Settings/Sections/HapticsSection.
// swift) — JIDesign has no JIPersistence dependency. The RN module-level `cached` /
// `intensityCached` sync reads are `JIHapticDispatcher.prefs` (Haptics.swift). Pure: `nonisolated`.

public nonisolated struct JIHapticsPrefs: Codable, Sendable, Equatable {
    /// `haptics.enabled.v1` — Settings toggle, default on. Disabled = no marker, no native call,
    /// no fallback at all.
    public var enabled: Bool
    /// `haptics.intensity.v1` — [1, 100], never 0 (CONTEXT-E24-HAPTICS §2b "Off vs. intensity=0":
    /// `enabled=false` is the ONLY way to mean "no haptics"). Default 100 = today's un-tunable
    /// amplitude exactly, so upgrading changes nobody's felt experience until they touch the slider.
    public var intensity: Int

    public init(enabled: Bool = JIHapticsPrefs.defaultEnabled, intensity: Int = JIHapticsPrefs.defaultIntensity) {
        self.enabled = enabled
        self.intensity = JIHapticsPrefs.clampIntensity(Double(intensity))
    }

    /// The RN pref keys, verbatim — two separate blobs (a Bool and a number), never one struct.
    public static let enabledKey = "haptics.enabled.v1"
    public static let intensityKey = "haptics.intensity.v1"

    public static let defaultEnabled = true
    public static let defaultIntensity = 100
    public static let `default` = JIHapticsPrefs()

    /// hapticsPrefs.ts `clampIntensity` — non-finite → the DEFAULT (a corrupt blob reads as
    /// "untouched"), else rounded into [1, 100]. (The slider's own clamp, which floors a
    /// non-finite to 1, is `JIHapticIntensity.clampPct`.)
    public static func clampIntensity(_ pct: Double) -> Int {
        guard pct.isFinite else { return defaultIntensity }
        return min(100, max(1, Int(pct.rounded())))
    }

    /// Reconciles two raw persisted blobs (either may be missing) into prefs — a missing key is
    /// its default, never the whole struct's.
    public static func reconcile(enabled: Bool?, intensity: Double?) -> JIHapticsPrefs {
        JIHapticsPrefs(enabled: enabled ?? defaultEnabled, intensity: intensity.map(clampIntensity) ?? defaultIntensity)
    }
}
