import Foundation
import SwiftUI
import JICore
import JIPersistence

// B-57 W4 (spec §3.3) — the user's safety settings. PrefStore `gate.settings` is the source of
// truth; `GateSettingsMirror` copies it to the hub for the 05:10 morning_go run.
// Toby 2026-09-24: JI is a product for any user. The cap is OPTIONAL, zones are the user's,
// "Avoid Zone 5" is a user toggle. Nothing here has an app default number.

/// How many consecutive low-HRV nights turn the call red. Balanced = the pre-W4 rule.
public nonisolated enum GatePreset: String, Codable, CaseIterable, Sendable {
    case cautious, balanced, push

    public var hrvLowNights: Int {
        switch self { case .cautious: 1; case .balanced: 2; case .push: 3 }
    }

    public var title: String {
        switch self { case .cautious: "Cautious"; case .balanced: "Balanced"; case .push: "Push" }
    }

    /// OnboardingGate board copy, verbatim.
    public var boardDescription: String {
        switch self {
        case .cautious: "Modified after one low HRV night. More easy days."
        case .balanced: "Modified after two low nights in a row. One bad night is treated as noise."
        case .push: "Modified after three low nights. Fewer easy days, more risk of training tired."
        }
    }

    /// GateConfig "How cautious" row subtitle (board: "Modified after 2 low HRV nights in a row").
    public var configSubtitle: String {
        switch self {
        case .cautious: "Modified after 1 low HRV night"
        case .balanced: "Modified after 2 low HRV nights in a row"
        case .push: "Modified after 3 low HRV nights in a row"
        }
    }
}

public nonisolated struct GateSettings: Codable, Equatable, Sendable {
    public static let recheckWeeks = 8
    /// Toby's pre-W4 install (cap 175, Avoid Zone 5 on, AWU3 zones), applied ONCE by
    /// `GateSettingsStore.migratePreW4InstallIfNeeded()`. Never a default for a new install.
    public static let legacyPreW4 = GateSettings(preset: .balanced, hrCapBpm: 175, avoidZone5: true, zones: .legacyPreW4)

    public var preset: GatePreset
    /// The user's cap, or nil = no cap. Never clamped, never changed by the app.
    public var hrCapBpm: Int?
    /// Optional user toggle: no session or Watch step targets the user's Zone 5. Needs `zones`.
    public var avoidZone5: Bool
    /// The user's zones (from max HR or LTHR, each floor editable). nil = not entered.
    public var zones: HrZones?
    /// yyyy-MM-dd of the last time the user answered the limit question (a number or "No") or
    /// confirmed the number. nil = never answered (a fresh skip, or the migrated pre-W4 value).
    public var hrCapConfirmedOn: String?

    public var hasCap: Bool { hrCapBpm != nil }
    public var hrCapChosen: Bool { hrCapConfirmedOn != nil }
    /// The Zone 5 floor to stay under, only when the user chose to avoid Zone 5 and has zones.
    public var zone5FloorBpm: Int? { avoidZone5 ? zones?.zone5FloorBpm : nil }
    public var workoutLimits: WorkoutHrLimits { WorkoutHrLimits(capBpm: hrCapBpm, zone5FloorBpm: zone5FloorBpm) }
    /// The hub mirror body (`PUT /planning/gate-settings`).
    public var body: GateSettingsBody {
        GateSettingsBody(preset: preset.rawValue, hrCapBpm: hrCapBpm, avoidZone5: avoidZone5, zoneFloorsBpm: zones?.floorsBpm)
    }

    public init(preset: GatePreset = .balanced, hrCapBpm: Int? = nil, avoidZone5: Bool = false,
                zones: HrZones? = nil, hrCapConfirmedOn: String? = nil) {
        self.preset = preset; self.hrCapBpm = hrCapBpm; self.avoidZone5 = avoidZone5
        self.zones = zones; self.hrCapConfirmedOn = hrCapConfirmedOn
    }

    enum CodingKeys: String, CodingKey { case preset, hrCapBpm, avoidZone5, zones, hrCapConfirmedOn }

    /// Field-by-field tolerant: a newer/older or damaged blob keeps whatever is readable. A
    /// missing or unreadable cap is "no cap" — the app never invents one.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = (try? c.decodeIfPresent(GatePreset.self, forKey: .preset)) ?? .balanced
        hrCapBpm = (try? c.decodeIfPresent(Int.self, forKey: .hrCapBpm)) ?? nil
        avoidZone5 = ((try? c.decodeIfPresent(Bool.self, forKey: .avoidZone5)) ?? nil) ?? false
        zones = ((try? c.decodeIfPresent(HrZones.self, forKey: .zones)) ?? nil).flatMap { $0.isValid ? $0 : nil }
        hrCapConfirmedOn = (try? c.decodeIfPresent(String.self, forKey: .hrCapConfirmedOn)) ?? nil
    }
}

public nonisolated let hrCapParseError = "Enter a whole number of beats per minute."

/// Trimmed ASCII whole number (sign allowed) or nil. No range: the cap is the user's choice.
public nonisolated func parseHrCap(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) else { return nil }
    return Int(t)
}

/// Decodes any stored JSON value — used only to ask "does this PrefStore key exist?".
private nonisolated struct AnyStoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}

public nonisolated struct GateSettingsStore: Sendable {
    public static let key = "gate.settings"
    /// Set on the first W4 launch, whatever the outcome: the migration decides exactly once.
    public static let migrationKey = "gate.settings.migratedPreW4"
    /// PrefStore keys that only a USED pre-W4 install has (none is written at first boot).
    /// All PrefStore (not UserDefaults — `hk.upload.lastSuccess` is UserDefaults, so it is not
    /// here). `GateSettingsTests.preW4MarkersArePrefStoreKeys` pins them to their owners.
    static let preW4Keys = ["reminders.prefs", "today.tileOrder", "config_overrides.morning_gate",
                            "weekly_plan.periodized", "today.gate.lastAnsweredLocalDay", "kpi_selection.prefs.v1"]

    private let prefs: PrefStore
    public init(prefs: PrefStore) { self.prefs = prefs }

    /// W-TGT: once the targets document exists (after the §5 import) this reads and writes its
    /// Limits + caution rule; before that, the `gate.settings` row the import carries over.
    public func load() -> GateSettings {
        if let doc = TargetsStore(prefs: prefs).loadIfPresent() { return GateSettings(targets: doc) }
        return ((try? prefs.get(Self.key, as: GateSettings.self)) ?? nil) ?? GateSettings()
    }

    public func save(_ settings: GateSettings) throws {
        let targets = TargetsStore(prefs: prefs)
        guard let doc = targets.loadIfPresent() else { return try prefs.set(Self.key, settings) }
        try targets.save(settings.applied(to: doc))
    }

    /// Toby 2026-09-24: his install keeps cap 175 + Avoid Zone 5 + his zones across the update.
    /// Runs once, before onboarding. A fresh install (no pre-W4 data) gets nothing.
    @discardableResult
    public func migratePreW4InstallIfNeeded() -> Bool {
        guard !has(Self.migrationKey) else { return false }
        defer { try? prefs.set(Self.migrationKey, true) }
        guard !has(Self.key), !has(TargetsStore.key), Self.preW4Keys.contains(where: has) else { return false }
        try? save(.legacyPreW4)
        return true
    }

    private func has(_ key: String) -> Bool {
        ((try? prefs.get(key, as: AnyStoredValue.self)) ?? nil) != nil
    }
}

/// ISO-date arithmetic for the 8-week re-check. UTC Gregorian, so DST never shifts a day.
public nonisolated enum HrCapRecheck {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func addDays(_ iso: String, _ n: Int) -> String {
        let f = formatter()
        guard let d = f.date(from: iso), let out = calendar.date(byAdding: .day, value: n, to: d) else { return iso }
        return f.string(from: out)
    }

    /// Confirmation + 56 days; if that is today or already past, tomorrow (an overdue check
    /// still asks, it never goes silent).
    public static func nextDue(confirmedOn: String, today: String) -> String {
        let due = addDays(confirmedOn, GateSettings.recheckWeeks * 7)
        return due > today ? due : addDays(today, 1)
    }
}

extension EnvironmentValues {
    /// Set by `RootTabView` from `GateSettingsStore`; read by SessionCoach/Training.
    @Entry public var gateSettings: GateSettings = GateSettings()
}
