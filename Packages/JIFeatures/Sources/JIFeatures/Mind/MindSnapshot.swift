import Foundation
import JIPersistence

/// E9 — derives a purely descriptive one-line reflection of today's mind check-in, for the Mind
/// tab's `MindSnapshotCard`. Oracle `mindSnapshot` (`mobile/src/mind/mindSnapshot.ts`).
///
/// Deliberately never uses a GO/RED/REDUCED word or any athletic-gate language — this is a
/// reflection ("a steady day"), not a prescription. The HIG no-diagnosis rail is the reason:
/// WHO-5/mood/check-in data is GDPR Art.9 special-category data, and the verdict-hero grammar is
/// inherently confident/imperative in a way that would misrepresent a mental-health surface as a
/// clinical judgment.
nonisolated public struct MindSnapshot: Sendable, Equatable {
    public let headline: String
    public let description: String
    public init(headline: String, description: String) { self.headline = headline; self.description = description }
}

public nonisolated func mindSnapshot(_ checkin: CheckIn?) -> MindSnapshot {
    guard let checkin else {
        return MindSnapshot(
            headline: "No check-in yet",
            description: "Log today's mood, stress, and energy to see a snapshot here."
        )
    }

    let valence = checkin.mood?.valence ?? 0 // -1...1
    let load = Double(checkin.stress - checkin.energy) // roughly -4...4; higher = heavier

    let headline: String
    if valence >= 0.5 && load <= -1 { headline = "A lighter day" }
    else if valence <= -0.5 || load >= 2 { headline = "A heavier day" }
    else { headline = "A steady day" }

    let description = "Stress \(checkin.stress)/5 · energy \(checkin.energy)/5 logged today."
    return MindSnapshot(headline: headline, description: description)
}
