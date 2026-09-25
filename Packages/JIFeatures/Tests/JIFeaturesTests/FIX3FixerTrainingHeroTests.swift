import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX3 fixer BUG-44 (board 3/01): the Training header reads "Full · Wed 23 Sep" with the synced
// pill on the same row, and the hero carries the session's exercise list + Start session.

private let wed23 = Date(timeIntervalSince1970: 1_790_157_600) // 2026-09-23 10:00 UTC
private let enGB = Locale(identifier: "en_GB")
private let utc = TimeZone(identifier: "UTC")!

@Test func trainingSubtitleLeadsWithTheVerdictWord() {
    let s = trainingSubtitle(verdict: "GO — Full Upper", isStale: false, date: wed23, locale: enGB, timeZone: utc)
    #expect(s.word == "Full")
    #expect(s.tone == .go)
    #expect(s.dateText == "Wed 23 Sep")
    #expect(s.text == "Full · Wed 23 Sep")
}

@Test func trainingSubtitleDropsAStaleOrMissingVerdict() {
    let stale = trainingSubtitle(verdict: "GO — Full Upper", isStale: true, date: wed23, locale: enGB, timeZone: utc)
    #expect(stale.word == nil)
    #expect(stale.text == "Wed 23 Sep")
    let none = trainingSubtitle(verdict: nil, isStale: false, date: wed23, locale: enGB, timeZone: utc)
    #expect(none.word == nil)
    #expect(none.text == "Wed 23 Sep")
}

@Test func trainingSubtitleReadsModifiedForReduced() {
    let s = trainingSubtitle(verdict: "REDUCED — Z2", isStale: false, date: wed23, locale: enGB, timeZone: utc)
    #expect(s.word == "Modified")
    #expect(s.tone == .amber)
}

private func ex(_ id: Int, _ session: String, _ name: String, kg: Double?, sets: Int?, sid: Int? = nil) -> Exercise {
    Exercise(exerciseId: id, sessionName: session, exerciseName: name, sets: sets, repsTarget: nil,
             currentWeightKg: kg, progressionStepKg: nil, sessionId: sid)
}

@Test func trainingHeroListsOnlyThePlannedSessionsExercises() {
    let all = [ex(1, "Full Upper", "Bench press", kg: 50, sets: 3, sid: 7),
               ex(2, "Full Upper", "Bent-over row", kg: 50, sets: 3, sid: 7),
               ex(3, "Legs", "Squat", kg: 80, sets: 5, sid: 8)]
    let rows = trainingHeroRows(exercises: all, session: PlannedSession(id: 7, name: "Full Upper", weekday: 2))
    #expect(rows.map(\.name) == ["Bench press", "Bent-over row"])
    #expect(rows.first?.load == "50.0 kg · 3 sets")
}

@Test func trainingHeroRowsSayDashNotAnInventedLoad() {
    let rows = trainingHeroRows(exercises: [ex(1, "Full Upper", "Plank", kg: nil, sets: nil)],
                                session: PlannedSession(id: 99, name: "Full Upper", weekday: 2))
    #expect(rows.map(\.name) == ["Plank"])           // no session id → matched by name
    #expect(rows.first?.load == "—")
}

@Test func trainingHeroIsEmptyWithoutAPlannedSession() {
    #expect(trainingHeroRows(exercises: [ex(1, "Full Upper", "Bench", kg: 50, sets: 3)], session: nil).isEmpty)
}

@Test func trainingHeroRowsOmitAZeroKgBodyweightLoad() {
    let rows = trainingHeroRows(exercises: [ex(1, "Full Upper", "Diamond Push-Up", kg: 0, sets: 3)],
                                session: PlannedSession(id: 99, name: "Full Upper", weekday: 2))
    #expect(rows.first?.load == "3 sets")
}
