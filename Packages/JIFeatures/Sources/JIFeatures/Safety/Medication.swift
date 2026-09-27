import Foundation
import JIDesign
import JIPersistence

// B-57 W4 — the user's medication, typed in by the user (Reminders "Medication" group or the
// onboarding Safety step) or, only if the LD spike passes, picked from Apple Health. Nothing is
// pre-filled. It drives the daily medication reminder and the daytime-HRV hold on KpiDetail.
// Daytime HRV is context-only (B-65): "set aside" changes display, never a verdict.

public nonisolated enum MedicationFrequency: String, Codable, CaseIterable, Sendable {
    case daily, someDays, notAnymore
    public var title: String {
        switch self { case .daily: "Daily"; case .someDays: "Some days"; case .notAnymore: "Not anymore" }
    }
}

public nonisolated enum MedicationAnswer: String, Codable, Sendable { case unconfirmed, yes, no }
public nonisolated enum MedicationSource: String, Codable, Sendable { case manual, appleHealth }

public nonisolated struct MedicationEntry: Codable, Equatable, Sendable {
    public var name: String
    public var dose: String
    public var usualTime: ReminderTime?
    public var worksForHours: Int?
    public var frequency: MedicationFrequency
    public var answer: MedicationAnswer
    public var source: MedicationSource

    public init(name: String = "", dose: String = "", usualTime: ReminderTime? = nil, worksForHours: Int? = nil,
                frequency: MedicationFrequency = .daily, answer: MedicationAnswer = .unconfirmed, source: MedicationSource = .manual) {
        self.name = name; self.dose = dose; self.usualTime = usualTime; self.worksForHours = worksForHours
        self.frequency = frequency; self.answer = answer; self.source = source
    }

    public var isNamed: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "08:30–20:30" — usual time plus how long it works, wrapping midnight. nil when either is unknown.
    public var windowText: String? {
        guard let t = usualTime, let h = worksForHours else { return nil }
        let end = ReminderScheduler.wrapMinutesOfDay(t.hour * 60 + t.minute + h * 60)
        return "\(ReminderScheduler.formatTime(hour: t.hour, minute: t.minute))–\(ReminderScheduler.formatTime(hour: end / 60, minute: end % 60))"
    }
}

public nonisolated struct MedicationStore: Sendable {
    public static let key = "safety.medication"
    private let prefs: PrefStore
    public init(prefs: PrefStore) { self.prefs = prefs }

    public func load() -> MedicationEntry? { (try? prefs.get(Self.key, as: MedicationEntry.self)) ?? nil }

    public func save(_ entry: MedicationEntry?) throws {
        if let entry { try prefs.set(Self.key, entry) } else { try prefs.remove(Self.key) }
    }
}

public nonisolated enum DaytimeHrvState: Equatable, Sendable {
    case contextOnly
    case onHold
    case setAside(window: String?)

    public var word: String {
        switch self {
        case .contextOnly: "Context only"
        case .onHold: "On hold · confirm below"
        case .setAside(let w?): "Set aside \(w)"
        case .setAside(nil): "Set aside · add how long it works"
        }
    }

    public var role: JIColorRole {
        switch self { case .onHold: .reduced; case .contextOnly, .setAside: .muted }
    }
}

/// Unnamed/absent → context only. Named but not yet answered → on hold. "Yes" (and still
/// taken) → set aside during its window. "No" or "Not anymore" → counts like any reading.
public nonisolated func daytimeHrvState(_ medication: MedicationEntry?) -> DaytimeHrvState {
    guard let m = medication, m.isNamed else { return .contextOnly }
    if m.frequency == .notAnymore { return .contextOnly }
    switch m.answer {
    case .unconfirmed: return .onHold
    case .no: return .contextOnly
    case .yes: return .setAside(window: m.windowText)
    }
}
