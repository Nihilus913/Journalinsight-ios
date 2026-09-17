import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

@MainActor
private func makeModel(now: @escaping () -> Date = { Date() }) -> MindViewModel {
    let db = try! AppDatabase.inMemory()
    return MindViewModel(
        checkins: CheckInStore(db: db),
        eventStore: EventStore(db: db),
        who5Store: Who5Store(db: db),
        now: now
    )
}

@Test @MainActor func checkInRoundTripsThroughTheViewModel() async {
    let model = makeModel()
    await model.load()
    #expect(model.checkedInToday == false)

    let n = NewCheckIn(date: todayISOString(), mood: .good, stress: 3, energy: 4, dosed: true, irritability: 2, restlessness: 1, appetite: 3, note: "ok")
    let ok = await model.upsertCheckin(n)
    #expect(ok)
    #expect(model.checkedInToday)
    #expect(model.today?.mood == .good)
    #expect(model.today?.dosed == true)
}

@Test @MainActor func eventRoundTripsThroughTheViewModel() async {
    let model = makeModel()
    await model.load()
    let n = NewMindEvent(date: todayISOString(), timeLocal: "10:00", type: .neck_pain, severity: 2, prodrome: [], triggers: "posture", note: nil)
    let ok = await model.addEvent(n)
    #expect(ok)
    #expect(model.events.count == 1)
    #expect(model.events.first?.type == .neck_pain)
}

@Test @MainActor func deleteEventRemovesItFromTheInMemoryList() async {
    let model = makeModel()
    await model.load()
    _ = await model.addEvent(NewMindEvent(date: todayISOString(), timeLocal: "10:00", type: .other, severity: 1, prodrome: [], triggers: "", note: nil))
    let id = model.events[0].id
    await model.deleteEvent(id)
    #expect(model.events.isEmpty)
}

@Test @MainActor func who5RoundTripsThroughTheViewModel() async {
    let model = makeModel()
    await model.load()
    let ok = await model.addWho5(NewWho5(date: todayISOString(), items: [4, 4, 3, 3, 2]))
    #expect(ok)
    #expect(model.latestWho5?.raw == 16)
    #expect(model.latestWho5?.pct == 64)
}

@Test @MainActor func snapshotReflectsTodaysCheckIn() async {
    let model = makeModel()
    await model.load()
    #expect(model.snapshot.headline == "No check-in yet")
    _ = await model.upsertCheckin(NewCheckIn(date: todayISOString(), mood: .great, stress: 1, energy: 5, dosed: false, irritability: nil, restlessness: nil, appetite: nil, note: nil))
    #expect(model.snapshot.headline == "A lighter day")
}

@Test @MainActor func who5DueIsTrueBeforeAnyEntryAndFalseRightAfterOne() async {
    let fixedNow = { Date(timeIntervalSince1970: 1_758_000_000) } // 2026-09-16
    let model = makeModel(now: fixedNow)
    await model.load()
    #expect(model.who5Due)
    _ = await model.addWho5(NewWho5(date: todayISOString(now: fixedNow()), items: [3, 3, 3, 3, 3]))
    #expect(model.who5Due == false)
}
