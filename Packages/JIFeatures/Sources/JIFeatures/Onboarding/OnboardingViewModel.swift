import Foundation
import Observation
import JICore
import JIDesign
import JIPersistence

/// B-57 W4 onboarding copy (boards `3 Plan & train/08–11`; *(plan)* lines are the plan's).
public nonisolated enum OnboardingCopy {
    public static let welcomeTitle = "Your morning call"
    public static let welcomeSubtitle = "Each morning JI makes one call for the day. You say Go or adjust it."
    public static let welcomeRows: [(word: String, role: JIColorRole, text: String)] = [
        (VerdictUserWord.full, .go, "Train as planned."),
        (VerdictUserWord.modified, .reduced, "Same day, easier. Intervals become easy Z2."),
        (VerdictUserWord.rest, .danger, "Walk and recover. The plan moves on tomorrow."),
    ]
    public static let welcomeFooter = "It reads overnight HRV, resting HR and sleep from Apple Health and compares each with your own normal, not with other people."
    public static let baselineTitle = "First, it learns your normal"
    public static let baselineSubtitle = "Your normal comes from your own nights. Until then the call is careful."
    public static let baselineExampleCaption = "The shaded part is your normal, 27–30. The dot is last night."
    public static let baselineFooter = "Wear your watch to bed. Nights without it are skipped, not counted as bad."
    public static let baselineSteps: [HowWeCalculateStep] = [   // (plan) copy
        HowWeCalculateStep(title: "Your nights, not other people's", body: "JI reads overnight HRV, resting HR and sleep from Apple Health."),
        HowWeCalculateStep(title: "The shaded band", body: "It is the range your recent nights usually fall in."),
        HowWeCalculateStep(title: "Missing nights", body: "A night without the watch is skipped. It never counts as a bad night."),
    ]
    public static let safetyTitle = "Your limits"
    public static let safetySubtitle = "These keep hard days safe. Only you change them."
    public static let safetyDoctorNote = "Have a heart condition? Use the limit your doctor gave you."
    // Toby 2026-09-24: the cap and the zones are the user's; nothing is filled in.
    public static let capQuestion = "Do you want a heart-rate limit?"
    public static let capYesNote = "Sessions warn you above this. Any number you choose."
    public static let capNoNote = "No limit: sessions and Watch workouts follow your plan and your zones."
    public static let capAnswerMissing = "Choose Yes or No."
    public static let zonesTitle = "Your zones"
    public static let zonesNote = "Enter your max heart rate or lactate threshold HR. JI works out five zones; you can move each edge later in Gate thresholds. Leave it empty to skip."
    public static let avoidZone5Title = "Avoid Zone 5"
    public static let avoidZone5Note = "Optional. Sessions and Watch workouts stay below your Zone 5."
    public static let safetyMedicationNote = "Some medications change heart rate and HRV. JI only uses what you confirm."
    public static let gateTitle = "How careful should it be?"
    public static let gateSubtitle = "This decides how fast a day turns Modified. You can change it later in Gate thresholds."

    public static func nightsValue(_ n: OnboardingViewModel.NightsProgress?) -> String { n.map { String($0.have) } ?? "—" }
    public static func nightsReason(_ n: OnboardingViewModel.NightsProgress?) -> String? {
        n == nil ? JIMissingReason.calibrating.rawValue : nil
    }
}

/// B-57 W4 — the four-step first-launch flow (morning call → normal → your limits → how careful).
/// Nothing is pre-filled on a fresh install; a re-run (GateConfig "Walk me through it again", or
/// Toby's migrated install) starts from what is stored.
@Observable @MainActor
public final class OnboardingViewModel {
    public enum Step: Int, CaseIterable, Sendable { case welcome, baseline, safety, gate }
    public nonisolated struct NightsProgress: Equatable, Sendable {
        public let have: Int, need: Int
        public init(have: Int, need: Int) { self.have = have; self.need = need }
    }

    public private(set) var step: Step = .welcome
    /// "Do you want a heart-rate limit?" — nil = not answered yet (Continue asks for it).
    public var wantsCap: Bool? { didSet { capError = nil } }
    public var hrCapText: String
    public private(set) var capError: String?
    public var zoneAnchor: HrZoneAnchor
    public var zoneAnchorText: String
    public private(set) var zoneError: String?
    public var avoidZone5: Bool
    public var preset: GatePreset
    public private(set) var medication: MedicationEntry?
    public private(set) var finished = false
    /// nil until a nights source exists: the card shows "— Calibrating", never a made-up count.
    public let nightsSoFar: NightsProgress?

    private let prefs: PrefStore
    private let mirror: GateSettingsMirror?
    private let reminderCenter: (any ReminderNotificationCenter)?
    private let today: () -> String
    private let stored: GateSettings

    public init(prefs: PrefStore, mirror: GateSettingsMirror?, reminderCenter: (any ReminderNotificationCenter)?,
                nightsSoFar: NightsProgress? = nil, today: @escaping () -> String = { ReminderScheduler.todayISO() }) {
        self.prefs = prefs; self.mirror = mirror; self.reminderCenter = reminderCenter
        self.nightsSoFar = nightsSoFar; self.today = today
        let s = GateSettingsStore(prefs: prefs).load()
        self.stored = s
        // Nothing is pre-filled unless the user (or the pre-W4 migration) stored it.
        self.wantsCap = s.hasCap ? true : (s.hrCapChosen ? false : nil)
        self.hrCapText = s.hrCapBpm.map(String.init) ?? ""
        self.zoneAnchor = s.zones?.anchor ?? .maxHr
        self.zoneAnchorText = s.zones.map { String($0.anchorBpm) } ?? ""
        self.avoidZone5 = s.avoidZone5
        self.preset = s.preset
        self.medication = MedicationStore(prefs: prefs).load()
    }

    /// The zones the Safety step would save: nil when the field is empty or not a number. The
    /// stored (possibly hand-edited) zones are kept when the anchor and its number are unchanged.
    public var zonesPreview: HrZones? {
        let t = zoneAnchorText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let bpm = parseHrCap(t), bpm > 0 else { return nil }
        if let z = stored.zones, z.anchor == zoneAnchor, z.anchorBpm == bpm { return z }
        let derived = HrZones.derived(anchor: zoneAnchor, bpm: bpm)
        return derived.isValid ? derived : nil
    }

    public var stepLabel: String { "Step \(step.rawValue + 1) of \(Step.allCases.count)" }
    public var primaryTitle: String { step == .gate ? "Use \(preset.title)" : "Continue" }

    /// Steps the typed number, else the stored one. With neither, nothing happens: the app never
    /// invents a starting number.
    public func bumpCap(_ delta: Int) {
        guard let base = parseHrCap(hrCapText) ?? stored.hrCapBpm else { return }
        hrCapText = String(base + delta)
        capError = nil
    }

    public func saveMedication(_ entry: MedicationEntry) {
        medication = entry.isNamed ? entry : nil
        try? MedicationStore(prefs: prefs).save(medication)
    }

    public func back() {
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    public func continueTapped() async {
        switch step {
        case .welcome, .baseline:
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        case .safety:
            guard let wants = wantsCap else { capError = OnboardingCopy.capAnswerMissing; return }
            if wants, parseHrCap(hrCapText) == nil { capError = hrCapParseError; return }
            capError = nil
            if !zoneAnchorText.trimmingCharacters(in: .whitespaces).isEmpty, zonesPreview == nil {
                zoneError = hrCapParseError; return
            }
            zoneError = nil
            step = .gate
        case .gate:
            await finish()
        }
    }

    /// "Skip for now": marks the flow done and changes nothing (no cap, no zones, no preset).
    public func skip() async {
        OnboardingGate.markCompleted(prefs)
        finished = true
    }

    private func finish() async {
        guard let wants = wantsCap else { step = .safety; capError = OnboardingCopy.capAnswerMissing; return }
        let cap: Int? = wants ? parseHrCap(hrCapText) : nil
        if wants && cap == nil { step = .safety; capError = hrCapParseError; return }
        let zones = zonesPreview
        let settings = GateSettings(preset: preset, hrCapBpm: cap, avoidZone5: avoidZone5 && zones != nil,
                                    zones: zones, hrCapConfirmedOn: today())
        if let mirror { await mirror.save(settings) } else { try? GateSettingsStore(prefs: prefs).save(settings) }
        if let reminderCenter {
            let scheduler = ReminderScheduler(center: reminderCenter)
            if let cap {
                _ = try? await scheduler.scheduleHrCapCheck(confirmedOn: today(), capBpm: cap, today: today())
            } else {
                scheduler.cancelHrCapCheck()          // no cap: nothing to re-check
            }
        }
        OnboardingGate.markCompleted(prefs)
        finished = true
    }
}

public extension OnboardingViewModel {
    /// Registry/sweep fixture on the in-memory fixture store, opened at `step`.
    static func fixture(step: Step) -> OnboardingViewModel? {
        guard let prefs = NativeFixtureStore.prefs else { return nil }
        let vm = OnboardingViewModel(prefs: prefs, mirror: nil, reminderCenter: nil, today: { "2026-09-24" })
        vm.step = step
        return vm
    }
}
