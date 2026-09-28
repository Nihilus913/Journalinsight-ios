import Foundation
import Observation
import JICore
import JICompute
import JIPersistence
#if canImport(UIKit)
import UIKit
#endif

// W5b-L3 (P-gate-config) → W-TGT L3: the Limits engine behind Settings › Targets (HR cap + its
// 8-week re-check reminder, zones, Avoid Zone 5, the caution preset) and the "How the morning
// call works" screen's walk-through. Every write goes through `GateSettingsStore` / the gate
// settings mirror, which (after the §5 import) write the ONE targets document.
// W-TGT (spec §4): the local morning-gate / KPI-rule overrides, the fixture preview and the live
// `plan.kpi_target` block ("Advanced") are gone — Rules are edited once, in Targets.
@Observable @MainActor
public final class GateConfigViewModel {
    // MARK: B-57 W4 gate settings (preset, optional user cap, user zones, Avoid Zone 5)

    /// The user's own settings (PrefStore `gate.settings`). Nothing is filled in by the app.
    public private(set) var gateSettings = GateSettings()
    /// False until the stored settings have been read once.
    public private(set) var loaded = false

    private let prefStore: PrefStore
    private let mirror: GateSettingsMirror?
    private let reminderCenter: (any ReminderNotificationCenter)?
    private let today: () -> String
    /// W-FIX5 W4-1: listens for the app becoming active while this screen is alive.
    @ObservationIgnored private var foregroundObserver: (any NSObjectProtocol)?

    /// The app-active notification (nil where UIKit is absent, e.g. host tests).
    public nonisolated static var appDidBecomeActive: Notification.Name? {
        #if canImport(UIKit)
        UIApplication.didBecomeActiveNotification
        #else
        nil
        #endif
    }

    /// `mirror` copies gate-settings changes to the hub; `reminderCenter` (re)schedules the 8-week
    /// cap re-check. Both nil in the gallery / tests that do not exercise them.
    public init(prefStore: PrefStore,
                mirror: GateSettingsMirror? = nil, reminderCenter: (any ReminderNotificationCenter)? = nil,
                foregroundNotification: Notification.Name? = GateConfigViewModel.appDidBecomeActive,
                today: @escaping () -> String = { ReminderScheduler.todayISO() }) {
        self.prefStore = prefStore
        self.mirror = mirror
        self.reminderCenter = reminderCenter
        self.today = today
        // W-FIX5 W4-1: an open GateConfig (or the shell's retained model) re-reads the flag after
        // the foreground push, so "Not on the hub yet" clears without leaving the screen.
        if mirror != nil, let foregroundNotification {
            foregroundObserver = NotificationCenter.default.addObserver(forName: foregroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in await self?.foregroundSync() }
            }
        }
    }

    isolated deinit { if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) } }

    /// W-FIX5 W4-1: retries a pending push (last-write-wins, so racing the app's own foreground
    /// push only repeats the same PUT) and re-reads the persisted flag.
    public func foregroundSync() async {
        await mirror?.pushIfPending()
        refreshHubStatus()
    }

    // MARK: - Load

    public func load() async { loadLocal() }

    public func loadLocal() {
        gateSettings = GateSettingsStore(prefs: prefStore).load()
        refreshHubStatus()
        loaded = true
    }

    // MARK: - B-57 W4 gate settings

    /// A change that has not reached the hub yet (GateConfig: "Not on the hub yet"). Observed
    /// state (W-B57-W4 fixer): refreshed from the mirror's persisted flag on load, after every
    /// save and on `refreshHubStatus()` — a computed PrefStore read never told the view the PUT
    /// had landed, so the label stayed after a successful save.
    public private(set) var hubPending = false

    /// Re-reads the mirror's pending flag (e.g. after the app's foreground push).
    public func refreshHubStatus() {
        let pending = mirror?.hubPending ?? false
        if hubPending != pending { hubPending = pending }
    }

    public var capValueText: String { gateSettings.hrCapBpm.map { "\($0) bpm" } ?? "None" }

    public var capSubtitle: String {
        switch (gateSettings.hasCap, gateSettings.hrCapChosen) {
        case (true, true): "You chose it in setup. The app never raises it."
        case (true, false): "From your earlier setup. Confirm or change it — the app never raises it."
        case (false, true): "You chose no limit. Tap to add one — only you change it."
        case (false, false): "No limit set. Tap to add one — only you change it."
        }
    }

    /// nil when there is no cap: the re-check row is not shown (Toby 2026-09-24).
    public var recheckSubtitle: String? {
        guard gateSettings.hasCap else { return nil }
        return "Confirm your HR cap every \(GateSettings.recheckWeeks) weeks. "
            + (gateSettings.hrCapConfirmedOn.map { "Last confirmed \($0)." } ?? "Not confirmed yet.")
            + " JI asks; you decide."
    }

    /// W-TGT: the stored document is the truth (a Targets rule edit may have changed the caution
    /// rule since this model loaded), so every write starts from it — never from a stale copy.
    private func syncFromStore() { gateSettings = GateSettingsStore(prefs: prefStore).load() }

    public func setPreset(_ preset: GatePreset) async {
        syncFromStore()
        gateSettings.preset = preset
        await persistSettings()
    }

    /// `nil` = the user removes the cap. Otherwise only a whole number is accepted (no range —
    /// the user's choice). Either answer counts as a confirmation.
    public func changeHrCap(_ text: String?) async -> Bool {
        syncFromStore()
        if let text {
            guard let cap = parseHrCap(text) else { return false }
            gateSettings.hrCapBpm = cap
        } else {
            gateSettings.hrCapBpm = nil
        }
        await confirm()
        return true
    }

    public func confirmHrCap() async {
        syncFromStore()
        await confirm()
    }

    private func confirm() async {
        gateSettings.hrCapConfirmedOn = today()
        await persistSettings()
        guard let reminderCenter else { return }
        let scheduler = ReminderScheduler(center: reminderCenter)
        if let cap = gateSettings.hrCapBpm {
            _ = try? await scheduler.scheduleHrCapCheck(confirmedOn: today(), capBpm: cap, today: today())
        } else {
            scheduler.cancelHrCapCheck()          // no cap: nothing to re-check
        }
    }

    /// Zones from the user's own max HR or LTHR (derived; each floor editable afterwards).
    public func setZones(anchor: HrZoneAnchor, bpmText: String) async -> Bool {
        guard let bpm = parseHrCap(bpmText), bpm > 0 else { return false }
        let zones = HrZones.derived(anchor: anchor, bpm: bpm)
        guard zones.isValid else { return false }
        syncFromStore()
        gateSettings.zones = zones
        await persistSettings()
        return true
    }

    /// One boundary changed by hand; rejected (nothing saved) when the floors stop ascending.
    public func editZone(_ zone: Int, floorText: String) async -> Bool {
        syncFromStore()
        guard let floor = parseHrCap(floorText),
              let next = gateSettings.zones?.editing(zone: zone, floorBpm: floor) else { return false }
        gateSettings.zones = next
        await persistSettings()
        return true
    }

    public func clearZones() async {
        syncFromStore()
        gateSettings.zones = nil
        gateSettings.avoidZone5 = false
        await persistSettings()
    }

    /// Optional user toggle; it needs zones (there is no built-in Zone 5).
    public func setAvoidZone5(_ on: Bool) async {
        syncFromStore()
        guard !on || gateSettings.zones != nil else { return }
        gateSettings.avoidZone5 = on
        await persistSettings()
    }

    /// "Walk me through it again": the onboarding flow over the stored settings.
    /// W-FIX5 W4-2: `recovery` gives "Nights so far" its real count (nil = "— Calibrating").
    public func makeOnboardingModel(recovery: RecoveryScoreResult? = nil) -> OnboardingViewModel {
        OnboardingViewModel(prefs: prefStore, mirror: mirror, reminderCenter: reminderCenter,
                            nightsSoFar: OnboardingViewModel.NightsProgress(recovery: recovery), today: today)
    }

    private func persistSettings() async {
        if let mirror { await mirror.save(gateSettings) } else { try? GateSettingsStore(prefs: prefStore).save(gateSettings) }
        refreshHubStatus()
    }
}

// MARK: - B-33 §8.5 fixture

public extension GateConfigViewModel {
    /// The Limits engine over an empty in-memory `PrefStore`, for `ScreenRegistry`/the
    /// screenshot sweep. `nil` only when an in-memory SQLite file cannot be opened.
    static func fixture() -> GateConfigViewModel? {
        guard let prefs = NativeFixtureStore.prefs else { return nil }
        let model = GateConfigViewModel(prefStore: prefs)
        model.loadLocal()
        return model
    }
}

/// W-FIX5 W4-2: the onboarding "Nights so far" card from the recovery score — the nights of
/// personal normal it has and the minimum it needs. nil without a result (never a guessed count).
extension OnboardingViewModel.NightsProgress {
    public init?(recovery: RecoveryScoreResult?) {
        guard let recovery else { return nil }
        self.init(have: recovery.nights, need: recovery.nightsNeeded)
    }
}
