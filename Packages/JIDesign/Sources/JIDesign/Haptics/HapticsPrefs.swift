import Foundation
import JICore

// W8-L1 (P-haptics). Port of `mobile/src/haptics/hapticsPrefs.ts`'s VALUES: the two persisted
// prefs (enabled — the sole master switch; intensity — only ever SCALES an already-permitted
// fire), their keys, defaults and clamp — and, since W-B31, their persistence too (RN
// `getLocalPref`/`setLocalPref`): `HapticsPrefsStore` below, over the JICore `JIPrefStoring` seam
// (JIDesign has no JIPersistence dependency; the app hands it `PrefStore`, which conforms). The RN
// module-level `cached` / `intensityCached` sync reads are `JIHapticDispatcher.prefs`
// (Haptics.swift). Pure: `nonisolated`.

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

// MARK: - HapticsPrefsStore (hapticsPrefs.ts over JIPrefStoring)

/// `loadHapticsEnabled` / `setHapticsEnabled` / `loadHapticsIntensity` / `setHapticsIntensity`.
/// Every write updates the dispatcher's synchronous cache FIRST, then the disk (RN: "updates
/// the sync cache immediately, before the disk write even resolves"). A failed read means
/// nothing persisted yet (defaults), never an error.
public nonisolated enum HapticsPrefsStore {
    public static let enabledKey = JIHapticsPrefs.enabledKey
    public static let intensityKey = JIHapticsPrefs.intensityKey

    /// The persisted prefs (defaults for a missing/corrupt blob, field by field).
    public static func load(from store: any JIPrefStoring) -> JIHapticsPrefs {
        let enabled = (try? store.get(enabledKey, as: Bool.self)) ?? nil
        let intensity = (try? store.get(intensityKey, as: Double.self)) ?? nil
        return JIHapticsPrefs.reconcile(enabled: enabled, intensity: intensity)
    }

    /// `ensureLoaded` — the once-per-launch read that catches the sync cache up with the disk.
    /// The app calls this at boot (`appWiring`), so a cold start defaults OPEN (haptics fire at
    /// 100) only until this runs.
    @MainActor public static func warm(from store: any JIPrefStoring, into dispatcher: JIHapticDispatcher = .shared) {
        dispatcher.prefs = load(from: store)
    }

    /// `setHapticsEnabled(enabled)`.
    @MainActor public static func setEnabled(_ enabled: Bool, store: any JIPrefStoring, dispatcher: JIHapticDispatcher = .shared) throws {
        dispatcher.prefs.enabled = enabled
        try store.set(enabledKey, enabled)
    }

    /// `setHapticsIntensity(pct)` — clamps to [1, 100]; 0 is never storable.
    @MainActor public static func setIntensity(_ pct: Double, store: any JIPrefStoring, dispatcher: JIHapticDispatcher = .shared) throws {
        let clamped = JIHapticsPrefs.clampIntensity(pct)
        dispatcher.prefs.intensity = clamped
        try store.set(intensityKey, clamped)
    }
}
