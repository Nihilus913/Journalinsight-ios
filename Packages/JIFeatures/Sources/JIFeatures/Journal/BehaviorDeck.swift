import Foundation
import JIPersistence

// W8-L2 (P-journal). Port of `mobile/src/lib/behaviorDeck.ts` (92 L): the framework-free logic
// behind the swipeable behaviour journal cards (E15-17) — deck order, the two standing
// constraints the deck checks in on, and the swipe-outcome resolution — so every branch is
// testable without rendering anything. `BehaviorAnswer`/`DeckResponses` live next to the store
// in JIPersistence (the oracle's `lib` type imported by its `data` store; Swift's dependency
// direction forces the reverse) and are re-exported here by `import JIPersistence`.

public nonisolated struct BehaviorCard: Sendable, Equatable, Identifiable {
    public let id: String
    /// Short label — the card's own title line.
    public let title: String
    /// The yes/no question itself.
    public let prompt: String
    /// One line grounding WHY this is asked (evidence-cited thresholds surfaced in the UI).
    public let detail: String

    public init(id: String, title: String, prompt: String, detail: String) {
        self.id = id; self.title = title; self.prompt = prompt; self.detail = detail
    }
}

public nonisolated enum BehaviorDeck {
    /// `BEHAVIOR_CARDS` verbatim: the two standing behavioural constraints this deck wires
    /// (memory/feedback_no_pre_workout_fueling.md, memory/user_reflux_carb_constraint.md). A
    /// fresh install (or a new day) always starts from this exact order.
    public static let cards: [BehaviorCard] = [
        BehaviorCard(
            id: "no-pre-workout-fueling",
            title: "No pre-workout fueling",
            prompt: "Did you avoid eating in the 3 hours before training today?",
            detail: "Standing rule: carbs 3h+ before or after a session, never right before — pre-workout eating has triggered nausea."
        ),
        BehaviorCard(
            id: "reflux-safe-carbs",
            title: "Reflux-safe carbs",
            prompt: "Did today's carbs come from reflux-safe sources, front-loaded before ~15:00?",
            detail: "Rice, Milchreis, potato, banana, berries, dextrin — other grain/carb sources have triggered reflux."
        ),
    ]

    /// `orderDeck`: a card already answered today drops out; the rest keep `cards`' own fixed
    /// order rather than being re-sorted by anything derived, so the deck is predictable across
    /// renders and across days. A duplicated id in `cards` is collapsed to its first occurrence
    /// (the same card can never be shown — or logged — twice for one day).
    public static func orderDeck(_ cards: [BehaviorCard], answered: DeckResponses) -> [BehaviorCard] {
        var seen = Set<String>()
        return cards.filter { card in
            guard answered[card.id] == nil, !seen.contains(card.id) else { return false }
            seen.insert(card.id)
            return true
        }
    }

    /// Fraction of the card's own measured width a horizontal drag must clear to commit
    /// (rather than snap back) — scales with the card so a narrow card doesn't need an
    /// implausibly long drag to match a wide one.
    public static let swipeDismissRatio: Double = 0.32

    /// Average horizontal velocity (pt/ms, across the whole gesture) that commits a swipe even
    /// short of the distance bar — a fast flick reads as decisive.
    public static let swipeVelocityThreshold: Double = 0.55

    /// How far (pt) a touch must travel, and how much more horizontally than vertically,
    /// before the deck claims the drag as a swipe (E16-12 swipe/scroll disambiguation).
    public static let horizontalIntent: Double = 6

    /// A cover-display-safe guess for the swipe-distance bar BEFORE the card has been measured.
    public static let preLayoutCardWidth: Double = 300

    /// `resolveSwipeOutcome`: given a released drag's signed horizontal distance `dx` (right is
    /// positive), its average velocity `vx` (same sign, pt/ms) and the card's width, returns
    /// `.yes` (right), `.no` (left) or `nil` — cleared neither bar, snap back unanswered.
    /// `cardWidth <= 0` is treated as 1 (never divides by zero; an unmeasured card gets the
    /// smallest possible bar rather than an unreachable one).
    public static func resolveSwipeOutcome(dx: Double, vx: Double, cardWidth: Double) -> BehaviorAnswer? {
        let width = cardWidth > 0 ? cardWidth : 1
        let distanceBar = width * swipeDismissRatio
        if dx > distanceBar || vx > swipeVelocityThreshold { return .yes }
        if dx < -distanceBar || vx < -swipeVelocityThreshold { return .no }
        return nil
    }

    /// E16-12 `onMoveShouldSetResponder`: claims the drag only once its cumulative movement is
    /// more horizontal than vertical AND past the dead zone; a vertical drag never crosses the
    /// gate and scrolls the parent instead. Reduced motion makes the gesture fully inert.
    public static func shouldClaimSwipe(dx: Double, dy: Double, reduceMotion: Bool) -> Bool {
        if reduceMotion { return false }
        return abs(dx) > horizontalIntent && abs(dx) > abs(dy)
    }

    /// `todayISO()`: the device-local calendar day the deck keys its answers under. A new day
    /// starts every card fresh — the date key itself IS the rollover, there is no reset step.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
