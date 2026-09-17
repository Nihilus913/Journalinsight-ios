import Foundation

/// WHO-5 Well-Being Index — pure scoring logic (oracle `mobile/src/mind/who5scoring.ts`). No
/// dependencies, no I/O.
///
/// WHO-5 is a well-being TREND instrument, never a diagnosis. `who5Message` is the single
/// safety-sensitive surface here: it must return exactly the approved below-threshold copy
/// (raw <= 12) or nil — nothing else, and never a clinical/diagnostic term.
public nonisolated let WHO5_ITEMS: [String] = [
    "I have felt cheerful and in good spirits",
    "I have felt calm and relaxed",
    "I have felt active and vigorous",
    "I woke up feeling fresh and rested",
    "My daily life has been filled with things that interest me",
]

nonisolated public struct Who5Response: Sendable, Equatable {
    public let value: Int
    public let label: String
    public init(value: Int, label: String) { self.value = value; self.label = label }
}

public nonisolated let WHO5_RESPONSES: [Who5Response] = [
    Who5Response(value: 5, label: "All of the time"),
    Who5Response(value: 4, label: "Most of the time"),
    Who5Response(value: 3, label: "More than half the time"),
    Who5Response(value: 2, label: "Less than half the time"),
    Who5Response(value: 1, label: "Some of the time"),
    Who5Response(value: 0, label: "At no time"),
]

// The ONLY below-threshold message allowed. Descriptive, gentle, doctor-referral framing —
// nothing stronger, nothing clinical. Do not change this string without re-reading the RAILS
// in the slice spec.
nonisolated private let LOW_SCORE_MESSAGE = "This has been on the lower side lately — worth mentioning to your doctor."

/// Returns the exact below-threshold message when raw <= 12, else nil. There is no other message
/// this function may ever return. Oracle `who5Message`.
public nonisolated func who5Message(_ raw: Int) -> String? {
    raw <= 12 ? LOW_SCORE_MESSAGE : nil
}
