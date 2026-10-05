import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// B-52 p5: the global offline / "N pending" marker and its per-kind rows.
@MainActor
@Suite struct B52PendingSyncMarkerTests {
    @Test func markerTextCoversAllFourStates() {
        #expect(pendingSyncMarkerText(pending: 0, offline: false) == nil)
        #expect(pendingSyncMarkerText(pending: 0, offline: true) == "Offline")
        #expect(pendingSyncMarkerText(pending: 3, offline: true) == "Offline · 3 pending")
        #expect(pendingSyncMarkerText(pending: 2, offline: false) == "2 waiting to sync")
    }

    @Test func everyKindTheAppEnqueuesHasAHumanLabel() {
        var kinds = OutboxDrainer.knownKinds
        kinds.insert(StrengthOutbox.kind)
        kinds.insert(WorkoutLibraryOutbox.kind)
        kinds.formUnion([B52WriteKinds.trainingBreak, B52WriteKinds.garminPush])   // B-52 p4 kinds
        for kind in kinds {
            #expect(pendingSyncKindLabel(kind) != kind, "kind \(kind) has no label")
        }
        #expect(pendingSyncKindLabel("future_kind") == "future_kind")   // never hidden
    }

    @Test func linesGroupByKindInFirstQueuedOrder() throws {
        let outbox = Outbox(db: try AppDatabase.inMemory())
        _ = try outbox.enqueue(kind: "weighin", payload: ["kg": 80.0])
        let s = try outbox.enqueue(kind: "strength", payload: ["id": 1])
        _ = try outbox.enqueue(kind: "weighin", payload: ["kg": 80.2])
        try outbox.markFailed(id: s, error: "offline")
        let lines = pendingSyncLines(try outbox.pending())
        #expect(lines.map { $0.kind } == ["weighin", "strength"])
        #expect(lines.map { $0.count } == [2, 1])
        #expect(lines[1].lastError == "offline")
    }

    @Test func modelCountsQueuedRowsAndClearsWhenDrained() throws {
        let db = try AppDatabase.inMemory()
        let outbox = Outbox(db: db)
        let model = PendingSyncModel(outboxSource: { outbox })
        model.refresh()
        #expect(model.markerText == nil)

        let a = try outbox.enqueue(kind: "weighin", payload: ["kg": 80.1])
        _ = try outbox.enqueue(kind: "exercise_patch", payload: ["id": 1])
        model.refresh()
        #expect(model.pendingCount == 2)
        #expect(model.markerText == "2 waiting to sync")

        try outbox.markSent(id: a)
        model.refresh()
        #expect(model.lines.map(\.kind) == ["exercise_patch"])
        for row in try outbox.pending() { try outbox.markSent(id: row.id) }
        model.refresh()
        #expect(model.markerText == nil)   // marker clears once the queue drains
    }
}
