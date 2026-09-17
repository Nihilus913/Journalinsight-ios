import Foundation

/// Ported verbatim from `mobile/src/journal/prompts.ts` (originally QuestionsDetailView's 3/day
/// deterministic window). `nonisolated` — see `JournalStreak`'s doc comment.
public nonisolated enum JournalPrompts {
    public static let PROMPTS: [String] = [
        "What are you grateful for today?",
        "What was the highlight of your day?",
        "What challenge did you face, and how did you handle it?",
        "What did you learn today?",
        "How are you feeling right now, and why?",
        "What's one thing you'd like to improve tomorrow?",
        "What's something you accomplished recently that you're proud of?",
        "If you could change one thing about today, what would it be?",
        "What are your intentions for tomorrow?",
        "How are you feeling?",
    ]

    private static func dayOfYear(_ d: Date) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: d)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 0)) else { return 0 }
        let diff = d.timeIntervalSince(start)
        return Int(diff / 86_400)
    }

    public static func todaysPrompts(_ d: Date) -> [String] {
        let start = (dayOfYear(d) * 3) % PROMPTS.count
        return (0..<3).map { PROMPTS[(start + $0) % PROMPTS.count] }
    }
}
