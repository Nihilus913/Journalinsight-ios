import Foundation

/// W-B38-B B-7 — the content state of the strength-session Live Activity (lock screen + Dynamic
/// Island). Foundation-only so the app (which requests the activity), the widget extension (which
/// draws it) and the package tests all share ONE type; `StrengthSessionActivityAttributes`
/// (`Widgets/Sources/`, two-target membership) uses it as its `ContentState`.
///
/// Every field that can be unknown is optional and is drawn as absent, never as a zero
/// (CLAUDE.md rule 5). `capBand` is computed by the producer from the user's own HR limit
/// (`SessionCoachViewModel.deriveCapState` / `SessionCap`) so the extension never re-derives it.
public nonisolated struct StrengthSessionActivityState: Codable, Hashable, Sendable {
    public enum CapBand: String, Codable, Hashable, Sendable { case unknown, noLimit, under, approaching, breach }

    public var exercise: String
    /// 1-based number of the set being worked (the next one to log while resting).
    public var setNumber: Int
    /// Planned sets for the exercise; nil when the plan does not say.
    public var setCount: Int?
    public var weightKg: Double?
    public var reps: Int?
    /// Timed sets (Plank, Dead Bug): the planned/last duration.
    public var durationS: Int?
    /// Rest countdown window; both nil when not resting.
    public var restStartedAt: Date?
    public var restEndsAt: Date?
    public var hrBpm: Int?
    /// The user's HR limit (cap and/or top of Zone 4). nil = the user set none.
    public var limitBpm: Int?
    public var capBand: CapBand
    public var updatedAt: Date

    public init(exercise: String, setNumber: Int, setCount: Int? = nil, weightKg: Double? = nil, reps: Int? = nil,
                durationS: Int? = nil, restStartedAt: Date? = nil, restEndsAt: Date? = nil, hrBpm: Int? = nil,
                limitBpm: Int? = nil, capBand: CapBand = .unknown, updatedAt: Date) {
        self.exercise = exercise
        self.setNumber = setNumber
        self.setCount = setCount
        self.weightKg = weightKg
        self.reps = reps
        self.durationS = durationS
        self.restStartedAt = restStartedAt
        self.restEndsAt = restEndsAt
        self.hrBpm = hrBpm
        self.limitBpm = limitBpm
        self.capBand = capBand
        self.updatedAt = updatedAt
    }

    /// "Set 2 of 4" / "Set 2" when the plan gives no count.
    public var setLine: String {
        if let setCount, setCount > 0 { return "Set \(setNumber) of \(setCount)" }
        return "Set \(setNumber)"
    }

    /// "52.5 kg × 8", "8 reps", "45 s", or nil when nothing is known yet.
    public var loadLine: String? {
        if let durationS { return "\(durationS) s" }
        switch (weightKg, reps) {
        case let (kg?, reps?): return "\(Self.kgText(kg)) kg × \(reps)"
        case let (kg?, nil): return "\(Self.kgText(kg)) kg"
        case let (nil, reps?): return "\(reps) reps"
        default: return nil
        }
    }

    /// "175" style limit text for "HR 150 / 175"; nil when there is no HR or no limit.
    public var hrLine: String? {
        guard let hrBpm else { return nil }
        if let limitBpm { return "\(hrBpm) / \(limitBpm) bpm" }
        return "\(hrBpm) bpm"
    }

    /// True while `now` is inside the rest window.
    public func isResting(at now: Date) -> Bool {
        guard let restStartedAt, let restEndsAt else { return false }
        return now >= restStartedAt && now < restEndsAt
    }

    /// 52.5 → "52.5", 60 → "60", 1.25 → "1.25".
    public static func kgText(_ kg: Double) -> String {
        if kg == kg.rounded() { return String(Int(kg)) }
        var s = String(format: "%.2f", kg)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
