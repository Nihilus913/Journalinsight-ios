import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// Port of `mobile/__tests__/journal/behaviorCardDeck.test.tsx` (18 tests) as ViewModel tests —
// the raw-responder gesture wiring, the persisted store round-trip, the Yes/No button fallback,
// the reduced-motion path, plus the Swift-only undo and day-rollover paths. The two Fold-width
// render tests have no ViewModel surface (SwiftUI lays the card out at `maxWidth: .infinity`).

private let first = BehaviorDeck.cards[0]
private let second = BehaviorDeck.cards[1]
private let date = "2026-08-31"
private let coverWidth = 344.0

@MainActor
private func makeVM(db: AppDatabase? = nil, date: String? = date, reduceMotion: Bool = false) throws -> (BehaviorDeckViewModel, BehaviorLogStore) {
    let store = BehaviorLogStore(prefs: PrefStore(db: try db ?? AppDatabase.inMemory()))
    let vm = BehaviorDeckViewModel(store: store, date: date)
    vm.reduceMotion = reduceMotion
    vm.load()
    vm.cardWidth = coverWidth
    return (vm, store)
}

/// A deliberate, unhurried drag: 400 ms keeps average velocity far under the flick threshold,
/// so only `dx` decides the outcome (mirrors the RN helper `dragTopCard`).
@MainActor private func drag(_ vm: BehaviorDeckViewModel, dx: Double, ms: Double = 400) -> BehaviorAnswer? {
    vm.releaseSwipe(dx: dx, elapsedMs: ms)
}

@Suite struct BehaviorDeckOrderingVMTests {
    @Test @MainActor func freshDayShowsFirstCard() throws {
        let (vm, _) = try makeVM()
        #expect(vm.top == first)
        #expect(vm.remaining == 2)
        #expect(!vm.isComplete)
    }

    @Test @MainActor func answeringFirstAdvancesToSecondInOrder() throws {
        let (vm, _) = try makeVM()
        vm.commit(first, .yes)
        #expect(vm.top == second)
        #expect(vm.deck.map(\.id) == [second.id])
    }

    @Test @MainActor func answeringEveryCardShowsCompletedState() throws {
        let (vm, _) = try makeVM()
        vm.commit(first, .yes)
        vm.commit(second, .no)
        #expect(vm.isComplete)
        #expect(vm.top == nil)
        #expect(vm.remaining == 0)
    }

    @Test @MainActor func persistedAnswerStartsDeckOnNextCard() throws {
        let db = try AppDatabase.inMemory()
        try BehaviorLogStore(prefs: PrefStore(db: db)).record(date: date, cardId: first.id, answer: .yes)
        let (vm, _) = try makeVM(db: db)
        #expect(vm.top == second)
    }

    @Test @MainActor func missingStoreReadsAsEmptyDayNotCrash() {
        let vm = BehaviorDeckViewModel(store: nil, date: date)
        vm.load()
        #expect(vm.top == first)
        vm.commit(first, .no)
        #expect(vm.top == second)
        #expect(vm.persistError == nil)
    }
}

@Suite struct BehaviorDeckSwipeVMTests {
    @Test @MainActor func rightwardDragPastBarLogsYesAndDismisses() throws {
        let (vm, store) = try makeVM()
        #expect(drag(vm, dx: coverWidth * 0.4) == .yes) // clears 344*0.32 comfortably
        #expect(vm.top == second)
        #expect(try store.load(date: date) == [first.id: .yes])
    }

    @Test @MainActor func leftwardDragPastBarLogsNoAndDismisses() throws {
        let (vm, store) = try makeVM()
        #expect(drag(vm, dx: -(coverWidth * 0.4)) == .no)
        #expect(vm.top == second)
        #expect(try store.load(date: date) == [first.id: .no])
    }

    @Test @MainActor func shortSlowDragSnapsBackNoRecord() throws {
        let (vm, store) = try makeVM()
        #expect(drag(vm, dx: 20) == nil) // well under 344*0.32 ≈ 110, dt=400 ms keeps velocity negligible
        #expect(vm.top == first)
        #expect(try store.load(date: date) == [:])
    }

    @Test @MainActor func fastFlickCommitsShortOfTheBar() throws {
        let (vm, store) = try makeVM()
        #expect(drag(vm, dx: 30, ms: 40) == .yes) // 0.75 pt/ms > 0.55
        #expect(try store.load(date: date) == [first.id: .yes])
    }

    @Test @MainActor func barScalesWithMeasuredCardWidth() throws {
        let (vm, _) = try makeVM()
        vm.cardWidth = 884 // unfolded: the same 120 pt drag no longer commits
        #expect(drag(vm, dx: 120) == nil)
        vm.cardWidth = coverWidth
        #expect(drag(vm, dx: 120) == .yes)
    }

    @Test @MainActor func buttonsAreAFullyEquivalentPath() throws {
        let (vm, store) = try makeVM()
        vm.commit(first, .no)
        #expect(try store.load(date: date) == [first.id: .no])
        #expect(vm.top == second)
    }

    @Test @MainActor func releaseOnEmptyDeckIsANoOp() throws {
        let (vm, store) = try makeVM()
        vm.commit(first, .yes); vm.commit(second, .yes)
        #expect(drag(vm, dx: coverWidth) == nil)
        #expect(try store.load(date: date) == [first.id: .yes, second.id: .yes])
    }
}

@Suite struct BehaviorDeckClaimGateVMTests {
    @Test @MainActor func verticalDragDoesNotClaim() throws {
        let (vm, _) = try makeVM()
        #expect(!vm.shouldClaimSwipe(dx: 2, dy: 40))
    }

    @Test @MainActor func wobbleUnderDeadZoneDoesNotClaim() throws {
        let (vm, _) = try makeVM()
        #expect(!vm.shouldClaimSwipe(dx: 3, dy: 1))
    }

    @Test @MainActor func horizontalDragClaimsThenCommitsEndToEnd() throws {
        let (vm, store) = try makeVM()
        #expect(vm.shouldClaimSwipe(dx: 40, dy: 2))
        #expect(drag(vm, dx: coverWidth * 0.4) == .yes)
        #expect(vm.top == second)
        #expect(try store.load(date: date) == [first.id: .yes])
    }

    @Test @MainActor func emptyDeckNeverClaims() throws {
        let (vm, _) = try makeVM()
        vm.commit(first, .yes); vm.commit(second, .yes)
        #expect(!vm.shouldClaimSwipe(dx: 40, dy: 2))
    }
}

@Suite struct BehaviorDeckReducedMotionVMTests {
    @Test @MainActor func moveBasedClaimingIsInertEitherDirection() throws {
        let (vm, _) = try makeVM(reduceMotion: true)
        #expect(!vm.shouldClaimSwipe(dx: 40, dy: 2))
        #expect(!vm.shouldClaimSwipe(dx: -40, dy: 2))
    }

    @Test @MainActor func dragThatWouldCommitDoesNothing() throws {
        let (vm, store) = try makeVM(reduceMotion: true)
        #expect(drag(vm, dx: coverWidth * 0.4) == nil)
        #expect(vm.top == first) // unchanged — no advance
        #expect(try store.load(date: date) == [:])
    }

    @Test @MainActor func buttonsRemainTheOneConcreteAction() throws {
        let (vm, store) = try makeVM(reduceMotion: true)
        vm.commit(first, .yes)
        #expect(vm.top == second)
        #expect(try store.load(date: date) == [first.id: .yes])
    }
}

@Suite struct BehaviorDeckUndoVMTests {
    @Test @MainActor func undoRemovesPersistedRowAndRestoresCard() throws {
        let (vm, store) = try makeVM()
        vm.commit(first, .yes)
        #expect(vm.undoEntry == BehaviorUndoEntry(card: first, answer: .yes))
        vm.undo()
        #expect(vm.top == first)
        #expect(vm.undoEntry == nil)
        #expect(try store.load(date: date) == [:])
    }

    @Test @MainActor func undoOnlyTakesBackTheMostRecentAnswer() throws {
        let (vm, store) = try makeVM()
        vm.commit(first, .yes)
        vm.commit(second, .no)
        #expect(vm.isComplete)
        vm.undo()
        #expect(vm.top == second)
        #expect(try store.load(date: date) == [first.id: .yes])
        vm.undo() // nothing left to undo — no-op
        #expect(vm.top == second)
    }

    @Test @MainActor func undoAfterSwipeWorksToo() throws {
        let (vm, store) = try makeVM()
        drag(vm, dx: -(coverWidth * 0.4))
        vm.undo()
        #expect(vm.top == first)
        #expect(try store.load(date: date) == [:])
    }
}

@Suite struct BehaviorDeckRolloverVMTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    @Test @MainActor func newLocalDayStartsEveryCardFreshAndDropsUndo() throws {
        let store = BehaviorLogStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
        var clock = DateComponents(calendar: utc, year: 2026, month: 8, day: 31, hour: 23, minute: 50).date!
        let vm = BehaviorDeckViewModel(store: store, now: { clock }, calendar: utc)
        vm.load()
        #expect(vm.day == "2026-08-31")
        vm.commit(first, .yes)
        #expect(vm.rolloverIfNeeded() == false) // same day — nothing happens
        clock = clock.addingTimeInterval(20 * 60) // 00:10 next day
        #expect(vm.rolloverIfNeeded())
        #expect(vm.day == "2026-09-01")
        #expect(vm.top == first)
        #expect(vm.undoEntry == nil)
        #expect(try store.load(date: "2026-08-31") == [first.id: .yes]) // yesterday untouched
    }

    @Test @MainActor func pinnedDateNeverRollsOver() throws {
        let (vm, _) = try makeVM()
        #expect(vm.rolloverIfNeeded() == false)
        #expect(vm.day == date)
    }
}
