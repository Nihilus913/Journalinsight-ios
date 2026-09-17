import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

private func checkIn(mood: Mood?, stress: Int, energy: Int) -> CheckIn {
    CheckIn(date: "2026-09-17", mood: mood, stress: stress, energy: energy, dosed: false, irritability: nil, restlessness: nil, appetite: nil, note: nil, updatedAt: "2026-09-17T00:00:00Z")
}

@Test func mindSnapshotShowsEmptyCopyFromNoCheckin() {
    let snap = mindSnapshot(nil)
    #expect(snap.headline == "No check-in yet")
    #expect(snap.description == "Log today's mood, stress, and energy to see a snapshot here.")
}

@Test func mindSnapshotIsALighterDayForGoodMoodAndLowLoad() {
    let snap = mindSnapshot(checkIn(mood: .great, stress: 1, energy: 4))
    #expect(snap.headline == "A lighter day")
}

@Test func mindSnapshotIsAHeavierDayForBadMoodOrHighLoad() {
    #expect(mindSnapshot(checkIn(mood: .terrible, stress: 3, energy: 3)).headline == "A heavier day")
    #expect(mindSnapshot(checkIn(mood: .okay, stress: 5, energy: 1)).headline == "A heavier day")
}

@Test func mindSnapshotIsASteadyDayOtherwise() {
    #expect(mindSnapshot(checkIn(mood: .okay, stress: 3, energy: 3)).headline == "A steady day")
}

@Test func mindSnapshotDescriptionAlwaysCitesStressAndEnergy() {
    let snap = mindSnapshot(checkIn(mood: .good, stress: 2, energy: 4))
    #expect(snap.description == "Stress 2/5 · energy 4/5 logged today.")
}

@Test func mindSnapshotNeverEmitsAVerdictWord() {
    let words = ["GO", "RED", "REDUCED"]
    for mood in Mood.allCases {
        for stress in 1...5 {
            for energy in 1...5 {
                let snap = mindSnapshot(checkIn(mood: mood, stress: stress, energy: energy))
                for w in words {
                    #expect(!snap.headline.uppercased().contains(w))
                }
            }
        }
    }
}
