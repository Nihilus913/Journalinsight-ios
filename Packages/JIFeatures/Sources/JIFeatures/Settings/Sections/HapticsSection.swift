import Foundation
import Observation
import SwiftUI
import JICore
import JIDesign
import JIPersistence

// W8-L1 (P-haptics). Port of `mobile/app/settings.tsx`'s `HapticsRow` ("Feel" card: the On/Off
// master switch, the device-capability caption, the intensity slider, the "Feel it" preview) +
// `HapticIntensitySlider.tsx` + the persistence half of `hapticsPrefs.ts` (`getLocalPref` /
// `setLocalPref` → `PrefStore`, SAME keys `haptics.enabled.v1` / `haptics.intensity.v1`, two
// separate blobs). Sits in RN's Preferences band after Appearance.

// MARK: - HapticsPrefsStore (hapticsPrefs.ts over PrefStore)

/// `loadHapticsEnabled` / `setHapticsEnabled` / `loadHapticsIntensity` / `setHapticsIntensity`.
/// Every write updates the dispatcher's synchronous cache FIRST, then the disk (RN: "updates
/// the sync cache immediately, before the disk write even resolves"). A failed read means
/// nothing persisted yet (defaults), never an error.
public nonisolated enum HapticsPrefsStore {
    public static let enabledKey = JIHapticsPrefs.enabledKey
    public static let intensityKey = JIHapticsPrefs.intensityKey

    /// The persisted prefs (defaults for a missing/corrupt blob, field by field).
    public static func load(from store: PrefStore) -> JIHapticsPrefs {
        let enabled = (try? store.get(enabledKey, as: Bool.self)) ?? nil
        let intensity = (try? store.get(intensityKey, as: Double.self)) ?? nil
        return JIHapticsPrefs.reconcile(enabled: enabled, intensity: intensity)
    }

    /// `ensureLoaded` — the once-per-launch read that catches the sync cache up with the disk.
    /// The app calls this at boot (`appWiring`), so a cold start defaults OPEN (haptics fire at
    /// 100) only until this runs.
    @MainActor public static func warm(from store: PrefStore, into dispatcher: JIHapticDispatcher = .shared) {
        dispatcher.prefs = load(from: store)
    }

    /// `setHapticsEnabled(enabled)`.
    @MainActor public static func setEnabled(_ enabled: Bool, store: PrefStore, dispatcher: JIHapticDispatcher = .shared) throws {
        dispatcher.prefs.enabled = enabled
        try store.set(enabledKey, enabled)
    }

    /// `setHapticsIntensity(pct)` — clamps to [1, 100]; 0 is never storable.
    @MainActor public static func setIntensity(_ pct: Double, store: PrefStore, dispatcher: JIHapticDispatcher = .shared) throws {
        let clamped = JIHapticsPrefs.clampIntensity(pct)
        dispatcher.prefs.intensity = clamped
        try store.set(intensityKey, clamped)
    }
}

// MARK: - HapticsViewModel (useHapticsEnabled / useHapticsIntensity + the slider's own loop)

/// The live state `HapticsRow` + `HapticIntensitySlider` read: starts from the dispatcher's
/// current cache (no flash of the default), stays in sync with every change made through it.
/// The slider owns both sides of the "where the thumb is → what it feels like" loop: it fires
/// `hapticSelection()` at each of the 5 detent crossings during a drag plus once on release,
/// through the same master toggle (dragging while Off still persists — silently — so the value
/// is ready the instant the switch flips back on).
@Observable @MainActor
public final class HapticsViewModel {
    public private(set) var enabled: Bool
    public private(set) var intensity: Int
    /// Non-nil after a `PrefStore` write failed (rule 5: never silent).
    public private(set) var saveError: String?

    private let store: PrefStore
    private let dispatcher: JIHapticDispatcher
    private var lastFiredBucket: Int
    private var dragging = false

    public init(prefs store: PrefStore, dispatcher: JIHapticDispatcher = .shared) {
        self.store = store
        self.dispatcher = dispatcher
        HapticsPrefsStore.warm(from: store, into: dispatcher)
        enabled = dispatcher.prefs.enabled
        intensity = dispatcher.prefs.intensity
        lastFiredBucket = JIHapticIntensity.detentBucket(forPct: dispatcher.prefs.intensity)
    }

    /// `settings.tsx` `hapticsCaption(getHapticCapabilities())`.
    public var capabilityCaption: String { JIHapticCapabilities.caption(dispatcher.player?.capabilities) }
    public var subtitle: String { "Vibration feedback on verdicts, PRs, saves, and selections · \(capabilityCaption)" }

    public func setEnabled(_ on: Bool) {
        enabled = on
        do { try HapticsPrefsStore.setEnabled(on, store: store, dispatcher: dispatcher); saveError = nil }
        catch { saveError = "Couldn't save the haptics setting — \(error.localizedDescription)" }
    }

    /// A live drag position (RN `handleMove`): tracks 1:1, ticks at detent crossings, no persist.
    public func dragTo(_ pct: Double) {
        dragging = true
        intensity = JIHapticIntensity.clampPct(pct)
        let bucket = JIHapticIntensity.detentBucket(forPct: intensity)
        if bucket != lastFiredBucket {
            lastFiredBucket = bucket
            dispatcher.fire(.selection)
        }
    }

    /// Release (RN `commitAndFeel`): persists and fires one more selection tick at the final value.
    public func commit(_ pct: Double) {
        dragging = false
        intensity = JIHapticIntensity.clampPct(pct)
        lastFiredBucket = JIHapticIntensity.detentBucket(forPct: intensity)
        do { try HapticsPrefsStore.setIntensity(Double(intensity), store: store, dispatcher: dispatcher); saveError = nil }
        catch { saveError = "Couldn't save the haptic intensity — \(error.localizedDescription)" }
        dispatcher.fire(.selection)
    }

    /// Accessibility increment/decrement — one detent-sized nudge, committed immediately.
    public func nudge(_ direction: Int) {
        commit(Double(intensity + direction.signum() * JIHapticIntensity.step))
    }

    /// `playHapticVocabularySample` — "Feel it": pressIn, selection @+100 ms, saveSuccess @+200 ms,
    /// verdictReveal(go) @+500 ms (RN `MOTION.duration.short2` = 100, `medium2` = 300).
    public func feelIt() {
        dispatcher.fire(.pressIn)
        let d = dispatcher
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100)); d.fire(.selection)
            try? await Task.sleep(for: .milliseconds(100)); d.fire(.saveSuccess)
            try? await Task.sleep(for: .milliseconds(300)); d.fire(.verdictReveal(.go))
        }
    }

    /// Re-reads the cache (another screen changed it) — RN's subscribe/notify.
    public func refresh() {
        if !dragging { intensity = dispatcher.prefs.intensity }
        enabled = dispatcher.prefs.enabled
    }
}

// MARK: - Section

/// RN "Preferences → Feel" card (`settings.tsx` `HapticsRow`).
public struct HapticsSection: SettingsSection {
    public static let sectionId = "w8.haptics"
    public let id = Self.sectionId
    public let title = "Haptics"
    public let systemImage = "iphone.radiowaves.left.and.right"
    public let sortKey = SettingsSortKey.preferences + 25
    public init() {}
    public var body: some View { HapticsSectionRows() }
}

private struct HapticsSectionRows: View {
    @Environment(SettingsViewModel.self) private var settings
    @State private var model: HapticsViewModel?

    var body: some View {
        Section("Feel") {
            if let model {
                HapticsRows(model: model)
            } else {
                SettingsLinkLabel(title: "Haptics", subtitle: "Preparing…")
                    .accessibilityIdentifier("settings.row.haptics.loading")
            }
        }
        .task { if model == nil { model = HapticsViewModel(prefs: settings.prefs) } }
    }
}

struct HapticsRows: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: HapticsViewModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) })) {
            SettingsLinkLabel(title: "Haptics", subtitle: model.subtitle)
        }
        .tint(theme.color(.info))
        .accessibilityLabel(model.enabled ? "Haptics On" : "Haptics Off")
        .accessibilityIdentifier("settings.haptics.enabled")

        HStack(spacing: 10) {
            HapticIntensitySlider(model: model)
            // §2b/§5: the hand-drawn pill is the system bordered button.
            Button("Feel it") { model.feelIt() }
                .buttonStyle(.bordered)
                .accessibilityLabel("Feel it")
                .accessibilityIdentifier("settings.haptics.feelIt")
        }
        .onAppear { model.refresh() }

        if let saveError = model.saveError {
            Text(saveError).jiFont(.caption).foregroundStyle(theme.color(.danger))
                .accessibilityIdentifier("settings.haptics.error")
        }
    }
}

/// `HapticIntensitySlider.tsx` — a continuous 1–100 track with 5 visual detent ticks; the haptic
/// TICK feedback is quantized to the detents (`dragTo`), the value is not. Dimmed (not disabled)
/// while the master switch is Off.
struct HapticIntensitySlider: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: HapticsViewModel

    var body: some View {
        Slider(
            value: Binding(get: { Double(model.intensity) }, set: { model.dragTo($0) }),
            in: Double(JIHapticIntensity.min)...Double(JIHapticIntensity.max),
            step: 1,
            onEditingChanged: { editing in if !editing { model.commit(Double(model.intensity)) } }
        )
        .tint(theme.color(.info))
        .opacity(model.enabled ? 1 : 0.45)
        .frame(minHeight: 48)
        .overlay(alignment: .center) { detentTicks }
        .accessibilityLabel("Haptic intensity")
        .accessibilityValue("\(model.intensity) percent")
        .accessibilityIdentifier("haptic-intensity-slider-pan")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.nudge(+1)
            case .decrement: model.nudge(-1)
            @unknown default: break
            }
        }
    }

    /// Decorative marks at the 5 detents — independent of the tick logic (that fires off the
    /// live position, not these marks).
    private var detentTicks: some View {
        GeometryReader { geo in
            ForEach(JIHapticIntensity.detents, id: \.self) { d in
                Rectangle().fill(theme.color(.bg).opacity(0.5))
                    .frame(width: 2, height: 8)
                    .position(x: geo.size.width * CGFloat(d) / 100, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
