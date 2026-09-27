import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-B57-W5 lane L3 guard tests (written first, green on the wave base): fixed rows whose files
// L3 touches — PF-01 / BUG-17 / BUG-18 (Decide CTA above the bar, session row opens Day, full-row
// reason hit), PF-02 / PF-10 (Day NEXT = Training's exercises, honest lunch reason), BUG-11
// (GoalsSetup strength rows match the hub's names).

private func l3GuardSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

struct B57W5L3GuardTests {
    private func ex(_ id: Int, _ session: String, _ name: String, kg: Double?, sets: Int?, weekday: Int? = nil) -> Exercise {
        Exercise(exerciseId: id, sessionName: session, exerciseName: name, sets: sets, repsTarget: "8",
                 currentWeightKg: kg, progressionStepKg: 2.5, weekday: weekday)
    }

    // MARK: PF-01 — Go / Adjust pinned above the floating tab bar

    @Test func pf01_decideActionsStayPinnedAboveTheBar() throws {
        #expect(decideActionsPinned(offscreen: false))
        #expect(decideActionBarBottomClearance(.compact) == tabBarBottomClearance(.compact))
        #expect(decideActionBarBottomClearance(.compact) > 0)
        let src = try l3GuardSource("Sources/JIFeatures/Today/DecideView.swift")
        let inset = try #require(src.range(of: ".safeAreaInset(edge: .bottom"))
        let tail = src[inset.upperBound...].prefix(700)
        #expect(tail.contains("decideActionBarBottomClearance("))
        #expect(tail.contains("today.decide.actions"))
    }

    // MARK: BUG-17 — the session row opens Day

    @Test func bug17_sessionRowOpensDay() throws {
        #expect(decideSessionRowOpensDay(syncing: false))
        #expect(!decideSessionRowOpensDay(syncing: true))
        let src = try l3GuardSource("Sources/JIFeatures/Today/DecideView.swift")
        let row = try #require(src.range(of: "\"today.decide.session\""))
        let head = src[..<row.lowerBound].suffix(1800)
        #expect(head.contains("Button { openDay() }"))
    }

    // MARK: BUG-18 — the whole reason row is hit-testable

    @Test func bug18_reasonRowIsFullWidthAndRectangular() throws {
        let src = try l3GuardSource("Sources/JIFeatures/Today/DecideView.swift")
        let fn = try #require(src.range(of: "private func reasonRow("))
        let body = src[fn.upperBound...].prefix(900)
        #expect(body.contains(".frame(maxWidth: .infinity"))
        #expect(body.contains(".contentShape(Rectangle())"))
    }

    // MARK: PF-02 — Day NEXT lists exactly Training's rows for the session

    @Test func pf02_dayNextRowsAreTrainingsRows() {
        let plan = [ex(1, "Day 1 Full Upper", "Barbell Row", kg: 50, sets: 3),
                    ex(2, "Day 3 Full Upper", "Barbell Bench Press", kg: 50, sets: 3, weekday: 4),
                    ex(3, "Day 3 Full Upper", "Pull-up", kg: 0, sets: 3, weekday: 4)]
        let card = dayNextCard(verdict: verdictParts("GO — Day 3 Full Upper + Z2 60min"), sessionForToday: "Day 3 Full Upper",
                               override: nil, plan: plan, weekday: 4)
        let training = trainingHeroRows(exercises: plan, session: dayPlannedSession(names: ["Day 3 Full Upper"], plan: plan, weekday: 4))
        #expect(card.rows == training)
        #expect(card.rows.map(\.name) == ["Barbell Bench Press", "Pull-up"])
        #expect(card.exercises == nil)
    }

    // MARK: PF-10 — the planned-lunch line gives a true reason

    @Test func pf10_plannedLunchIsHonest() {
        #expect(!dayPlannedLunchText.contains(JIMissingReason.notInHealthYet.rawValue))
        #expect(!dayPlannedLunchText.contains(JIMissingReason.noData.rawValue))
        #expect(dayPlannedLunchText.contains("meal plan"))
    }

    // MARK: BUG-11 — GoalsSetup strength rows find the hub's lift names

    @Test func bug11_goalsSetupRowsMatchHubNames() {
        let e = [StrengthStateEntry(exerciseId: 1, exerciseName: "Barbell Bench Press", currentWeightKg: 50, progressionStepKg: 2.5,
                                    sets: 3, repsTarget: 8, updatedAt: "2026-09-20T10:00:00Z", synced: true),
                 StrengthStateEntry(exerciseId: 2, exerciseName: "Barbell Row", currentWeightKg: 47.5, progressionStepKg: 2.5,
                                    sets: 3, repsTarget: 8, updatedAt: "2026-09-20T10:00:00Z", synced: true)]
        #expect(nextWorkingWeights(entries: e) == [NextWorkingWeight(name: "Bench press", kg: 50),
                                                   NextWorkingWeight(name: "Bent-over row", kg: 47.5)])
        #expect(nextWorkingWeights(entries: []).allSatisfy { $0.kg == nil })
    }
}
