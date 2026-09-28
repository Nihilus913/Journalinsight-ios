import SwiftUI
import JICore
import JIPersistence

// W-TGT L1 — the accessors every consumer reads targets through (spec §3 invariant b):
// `TargetsStore(prefs:).load()` off-view, `@Environment(\.targets)` in views, and the bridges
// below so the B-73 / B-57 W4 shapes (`MacroGoals`, `GateSettings`) read the ONE document.

public extension EnvironmentValues {
    /// The user's targets document. nil = not injected (previews); a view then shows no goal,
    /// no limit and recommended rules — never a number of its own.
    @Entry var targets: TargetsDocument? = nil
}

public nonisolated extension NutritionGoalsSnapshot {
    /// The nutrition goals every Fuel / KPI / Nutrition surface draws against, from the document.
    init(targets: TargetsDocument) { self.init(macros: targets.macroGoals) }
}

public nonisolated extension GatePreset {
    /// The caution rule (consecutive low-HRV nights) as a preset: ≤1 cautious, 2 balanced, ≥3 push.
    /// nil (never changed) = the recommended rule = balanced.
    init(hrvLowNights: Double?) {
        switch hrvLowNights.map({ Int($0.rounded()) }) {
        case let n? where n <= 1: self = .cautious
        case let n? where n >= 3: self = .push
        default: self = .balanced
        }
    }
}

public nonisolated extension GateSettings {
    /// The Limits + caution rule of a document, in the W4 shape (Watch limits, Training, Reminders).
    init(targets: TargetsDocument) {
        self.init(preset: GatePreset(hrvLowNights: targets.rules[.hrvLowNights]),
                  hrCapBpm: targets.limits.hrCapBpm, avoidZone5: targets.limits.avoidZone5,
                  zones: targets.limits.zones, hrCapConfirmedOn: targets.limits.hrCapConfirmedOn)
    }

    /// `document` with these settings written into its Limits and caution rule (nothing else).
    func applied(to document: TargetsDocument) -> TargetsDocument {
        var d = document
        d.limits = TargetLimits(hrCapBpm: hrCapBpm, hrCapConfirmedOn: hrCapConfirmedOn, zones: zones, avoidZone5: avoidZone5)
        d.rules[.hrvLowNights] = Double(preset.hrvLowNights)
        return d
    }
}
