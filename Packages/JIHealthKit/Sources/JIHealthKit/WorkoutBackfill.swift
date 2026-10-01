import Foundation

/// How far back the FIRST Apple-workout upload reaches (Toby 2026-09-28: a Settings choice,
/// 30 days by default). Stored in the App-Group suite next to the workout anchor. Widening the
/// window clears the anchor so the next pass re-sends from the new start — the hub keys workouts
/// by UUID, so a re-send is an update, never a duplicate. Narrowing never deletes anything
/// already on the hub (W-B81 X-1) and keeps the anchor.
public enum WorkoutBackfill: Int, CaseIterable, Sendable, Identifiable {
    case days30 = 30, days90 = 90, days120 = 120, year = 365, all = -1

    public static let key = "hk.upload.workouts.backfillDays"
    public static let `default`: WorkoutBackfill = .days30

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .days30: "30 days"
        case .days90: "90 days"
        case .days120: "120 days"
        case .year: "1 year"
        case .all: "Everything"
        }
    }

    /// Start of the first-sync window; nil = everything HealthKit holds.
    public func since(now: Date) -> Date? {
        self == .all ? nil : now.addingTimeInterval(-Double(rawValue) * 86_400)
    }

    private var span: Int { self == .all ? Int.max : rawValue }

    public static func current(_ defaults: UserDefaults?) -> WorkoutBackfill {
        guard let raw = defaults?.object(forKey: key) as? Int else { return .default }
        return WorkoutBackfill(rawValue: raw) ?? .default
    }

    public static func set(_ choice: WorkoutBackfill, defaults: UserDefaults?) {
        let previous = current(defaults)
        defaults?.set(choice.rawValue, forKey: key)
        if choice.span > previous.span { defaults?.removeObject(forKey: HealthKitUploader.workoutAnchorKey) }
    }
}
