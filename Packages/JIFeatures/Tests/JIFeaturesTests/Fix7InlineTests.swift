import Foundation
import Testing
@testable import JIFeatures

// W-FIX7 verify r2 leftovers, fixed inline by the orchestrator.
@Test func workoutsAndFoodRowsShowTheLocalHealthRead() {
    let rows = healthReadRowsArrival(capabilities: [.hrvRMSSD], lastUpload: nil, local: HealthLocalReads(workouts: true, food: true))
    #expect(rows.first { $0.title == "Workouts" }?.status.word == "Read on iPhone")
    #expect(rows.first { $0.title == "Food" }?.status.word == "Read on iPhone")
    #expect(!rows.contains { $0.status.word == "Not read yet" })
}

@Test func moreAppleHealthRowSaysConnectedWhenHealthWasReadLocally() {
    #expect(moreAppleHealthText(lastUpload: nil, readLocally: true) == "Read on iPhone")
    #expect(moreAppleHealthText(lastUpload: nil) == "No data yet")
}
