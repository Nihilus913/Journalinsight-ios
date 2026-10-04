import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// B-24 P2: the Mind check-in -> Apple Health mood mirror wiring (fake mirror, no HealthKit).

private actor FakeMoodMirror: MoodMirroring {
    var payloads: [MoodMirrorPayload] = []
    var authCalls = 0
    let grant: Bool
    let fails: Bool
    init(grant: Bool = true, fails: Bool = false) { self.grant = grant; self.fails = fails }
    func requestAuthorization() async throws -> Bool { authCalls += 1; return grant }
    func mirror(_ payload: MoodMirrorPayload) async throws {
        payloads.append(payload)
        if fails { throw CocoaError(.fileWriteUnknown) }
    }
}

private let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)

@MainActor
private func makeModel(_ mirror: FakeMoodMirror, enabled: Bool) -> MindViewModel {
    let db = try! AppDatabase.inMemory()
    return MindViewModel(checkins: CheckInStore(db: db), eventStore: EventStore(db: db), who5Store: Who5Store(db: db),
                         now: { fixedNow },
                         moodMirror: mirror, mirrorEnabled: { enabled })
}

private func checkIn(_ mood: JIPersistence.Mood?, note: String? = "private note") -> NewCheckIn {
    NewCheckIn(date: todayISOString(now: fixedNow), mood: mood, stress: 4, energy: 2, dosed: true,
               irritability: nil, restlessness: nil, appetite: nil, note: note)
}

@MainActor @Suite struct MoodMirrorTests {
    @Test func b24_toggleOff_neverMirrors() async {
        let fake = FakeMoodMirror()
        let model = makeModel(fake, enabled: false)
        #expect(await model.upsertCheckin(checkIn(.good)))
        await model.mirrorTask?.value
        #expect(await fake.payloads.isEmpty)
    }

    @Test func b24_toggleOn_onePayloadPerSave_moodOnly() async {
        let fake = FakeMoodMirror()
        let model = makeModel(fake, enabled: true)
        #expect(await model.upsertCheckin(checkIn(.good)))
        await model.mirrorTask?.value
        #expect(await model.upsertCheckin(checkIn(.bad)))
        await model.mirrorTask?.value
        let sent = await fake.payloads
        #expect(sent.map(\.valence) == [0.5, -0.5])
        #expect(sent.allSatisfy { $0.date == todayISOString(now: fixedNow) })
        #expect(sent.first?.updatedAt == fixedNow)
        // Structural guard: the payload can only carry day, valence and save time.
        let fields = Mirror(reflecting: sent[0]).children.compactMap(\.label)
        #expect(fields.sorted() == ["date", "updatedAt", "valence"])
        #expect(!String(describing: sent).contains("private note"))
    }

    @Test func b24_writerThrows_saveStillSucceeds() async {
        let fake = FakeMoodMirror(fails: true)
        let model = makeModel(fake, enabled: true)
        #expect(await model.upsertCheckin(checkIn(.great)))
        await model.mirrorTask?.value
        #expect(model.today?.mood == .great)
        #expect(model.phase == .loaded)
        #expect(await fake.payloads.count == 1)
    }

    @Test func b24_noMood_skipsWrite() async {
        let fake = FakeMoodMirror()
        let model = makeModel(fake, enabled: true)
        #expect(await model.upsertCheckin(checkIn(nil)))
        await model.mirrorTask?.value
        #expect(await fake.payloads.isEmpty)
    }

    @Test func b24_settingsToggle_offByDefault_onRequestsAuth() async {
        let defaults = UserDefaults(suiteName: "b24.\(UUID().uuidString)")!
        let fake = FakeMoodMirror()
        let settings = MoodMirrorSettingsModel(mirror: fake, defaults: defaults)
        #expect(settings.enabled == false)
        #expect(MoodMirrorPrefs.isEnabled(defaults) == false)
        await settings.setEnabled(true)
        #expect(await fake.authCalls == 1)
        #expect(settings.enabled && MoodMirrorPrefs.isEnabled(defaults))
        await settings.setEnabled(false)
        #expect(!settings.enabled && !MoodMirrorPrefs.isEnabled(defaults))
        #expect(await fake.authCalls == 1)
    }

    @Test func b24_settingsToggle_deniedStaysOff() async {
        let defaults = UserDefaults(suiteName: "b24.\(UUID().uuidString)")!
        let settings = MoodMirrorSettingsModel(mirror: FakeMoodMirror(grant: false), defaults: defaults)
        await settings.setEnabled(true)
        #expect(!settings.enabled && settings.denied && !MoodMirrorPrefs.isEnabled(defaults))
    }
}
