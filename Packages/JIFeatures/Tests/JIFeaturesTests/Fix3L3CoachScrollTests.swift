import Testing
import CoreGraphics
@testable import JIFeatures

// W-FIX3 L3 C-g: with the Coach overlay up, Today still scrolls its last cards (squares, footer)
// into view — the room reserved under the content is the card's MEASURED height, not a fixed
// 140 pt that an AX3 or two-line card (≈ 230 pt with the tab-bar clearance) outgrew.
@Test func theReservedRoomFollowsTheCardsRealHeight() {
    #expect(todayCoachScrollReserve(cardHeight: 230) >= 230)
    #expect(todayCoachScrollReserve(cardHeight: 520) >= 520)
    #expect(todayCoachScrollReserve(cardHeight: 520) > todayCoachScrollReserve(cardHeight: 230))
}

@Test func beforeTheCardIsMeasuredTheOldFloorStillHolds() {
    #expect(todayCoachScrollReserve(cardHeight: 0) >= 140)
}
