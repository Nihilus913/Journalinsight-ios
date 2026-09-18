import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// Port of `mobile/__tests__/lib/behaviorDeck.test.ts` (12 tests) + the E16-12 claim gate and the
// day-key helper (the RN component test's disambiguation cases, moved down to the pure layer).

private let coverWidth = 344.0 // Z Fold 8 cover display
private let expandedWidth = 884.0 // Z Fold 8 unfolded
private func card(_ id: String) -> BehaviorCard { BehaviorCard(id: id, title: id.uppercased(), prompt: "\(id)?", detail: "") }

@Suite struct OrderDeckTests {
    @Test func nothingAnsweredReturnsEveryCardInFixedOrder() {
        #expect(BehaviorDeck.orderDeck(BehaviorDeck.cards, answered: [:]) == BehaviorDeck.cards)
    }

    @Test func answeredCardDropsOutRestKeepOrder() {
        let cards = [card("a"), card("b"), card("c")]
        #expect(BehaviorDeck.orderDeck(cards, answered: ["b": .yes]).map(\.id) == ["a", "c"])
    }

    @Test func everyCardAnsweredIsEmptyDeck() {
        let cards = [card("a"), card("b")]
        #expect(BehaviorDeck.orderDeck(cards, answered: ["a": .no, "b": .yes]).isEmpty)
    }

    @Test func behaviorCardsCarryTheTwoStandingConstraintsInOrder() {
        #expect(BehaviorDeck.cards.map(\.id) == ["no-pre-workout-fueling", "reflux-safe-carbs"])
    }

    @Test func duplicateIdsAreDeduped() {
        let cards = [card("a"), card("b"), card("a")]
        #expect(BehaviorDeck.orderDeck(cards, answered: [:]).map(\.id) == ["a", "b"])
    }
}

@Suite struct ResolveSwipeOutcomeTests {
    @Test func pastPositiveDistanceBarResolvesYes() {
        let bar = coverWidth * BehaviorDeck.swipeDismissRatio
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: bar + 1, vx: 0, cardWidth: coverWidth) == .yes)
    }

    @Test func pastNegativeDistanceBarResolvesNo() {
        let bar = coverWidth * BehaviorDeck.swipeDismissRatio
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: -bar - 1, vx: 0, cardWidth: coverWidth) == .no)
    }

    @Test func shortSlowDragSnapsBack() {
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 10, vx: 0, cardWidth: coverWidth) == nil)
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: -10, vx: 0, cardWidth: coverWidth) == nil)
    }

    @Test func exactlyAtTheBarDoesNotCommit() {
        let bar = coverWidth * BehaviorDeck.swipeDismissRatio
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: bar, vx: 0, cardWidth: coverWidth) == nil)
    }

    @Test func fastFlickCommitsEvenWithSmallDistance() {
        let v = BehaviorDeck.swipeVelocityThreshold
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 5, vx: v + 0.01, cardWidth: coverWidth) == .yes)
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: -5, vx: -v - 0.01, cardWidth: coverWidth) == .no)
    }

    @Test func flickJustUnderThresholdDoesNotCommit() {
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 5, vx: BehaviorDeck.swipeVelocityThreshold - 0.01, cardWidth: coverWidth) == nil)
    }

    @Test func distanceBarScalesWithCardWidth() {
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 120, vx: 0, cardWidth: coverWidth) == .yes) // 344*0.32 ≈ 110
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 120, vx: 0, cardWidth: expandedWidth) == nil) // 884*0.32 ≈ 283
    }

    @Test func nonPositiveWidthNeverDividesByZero() {
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: 1, vx: 0, cardWidth: 0) == .yes)
        #expect(BehaviorDeck.resolveSwipeOutcome(dx: -1, vx: 0, cardWidth: -50) == .no)
    }
}

@Suite struct SwipeClaimGateTests {
    @Test func mostlyVerticalDragDoesNotClaim() {
        #expect(!BehaviorDeck.shouldClaimSwipe(dx: 2, dy: 40, reduceMotion: false))
    }

    @Test func wobbleUnderDeadZoneDoesNotClaim() {
        #expect(!BehaviorDeck.shouldClaimSwipe(dx: 3, dy: 1, reduceMotion: false))
    }

    @Test func clearlyHorizontalDragClaims() {
        #expect(BehaviorDeck.shouldClaimSwipe(dx: 40, dy: 2, reduceMotion: false))
        #expect(BehaviorDeck.shouldClaimSwipe(dx: -40, dy: 2, reduceMotion: false))
    }

    @Test func reducedMotionIsFullyInert() {
        #expect(!BehaviorDeck.shouldClaimSwipe(dx: 40, dy: 2, reduceMotion: true))
        #expect(!BehaviorDeck.shouldClaimSwipe(dx: -40, dy: 2, reduceMotion: true))
    }
}

@Suite struct DayKeyTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    @Test func formatsLocalCalendarDayZeroPadded() {
        let date = DateComponents(calendar: utc, year: 2026, month: 8, day: 3, hour: 9).date!
        #expect(BehaviorDeck.dayKey(for: date, calendar: utc) == "2026-08-03")
    }

    @Test func keyRollsOverAtLocalMidnightNotUTC() {
        var zurich = Calendar(identifier: .gregorian); zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-08-31 23:30 UTC is already 2026-09-01 01:30 in Zurich.
        let date = DateComponents(calendar: utc, year: 2026, month: 8, day: 31, hour: 23, minute: 30).date!
        #expect(BehaviorDeck.dayKey(for: date, calendar: utc) == "2026-08-31")
        #expect(BehaviorDeck.dayKey(for: date, calendar: zurich) == "2026-09-01")
    }
}
