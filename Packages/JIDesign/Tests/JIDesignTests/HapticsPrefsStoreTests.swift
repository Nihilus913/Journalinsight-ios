import Foundation
import os
import Testing
import JICore
@testable import JIDesign

// W-B31 R-2 (P-haptics). `HapticsPrefsStore` now lives in JIDesign over the JICore
// `JIPrefStoring` seam — these pin it against an in-memory fake (no JIPersistence here). The 13
// ported RN hapticsPrefs tests stay in JIFeatures (`HapticsPrefsTests`, over the real PrefStore).

/// In-memory `JIPrefStoring`: JSON blobs per key, like the `pref` table. `corrupt` = every read throws.
private final class FakePrefStore: JIPrefStoring {
    private let blobs = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])
    let corrupt: Bool
    init(corrupt: Bool = false) { self.corrupt = corrupt }
    struct Corrupt: Error {}
    func get<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        if corrupt { throw Corrupt() }
        return try blobs.withLock { $0[key] }.map { try JSONDecoder().decode(T.self, from: $0) }
    }
    func set<T: Encodable>(_ key: String, _ value: T) throws {
        let blob = try JSONEncoder().encode(value)
        blobs.withLock { $0[key] = blob }
    }
    func remove(_ key: String) throws { _ = blobs.withLock { $0.removeValue(forKey: key) } }
}

/// Own no-op fallback (not `HapticVocabularyTests`' `RecordingFallback` — that file is another wave's).
@MainActor
private final class SilentFallback: JIHapticFallbackPlayer {
    func play(_ fallback: JIHapticFallback) {}
}

@Suite(.serialized)
@MainActor
struct HapticsPrefsStoreTests {
    private func dispatcher() -> JIHapticDispatcher {
        let d = JIHapticDispatcher(player: nil, fallback: SilentFallback())
        d.marker = { _ in }
        return d
    }

    @Test func warmReadsThePersistedPrefsIntoTheDispatcher() throws {
        let store = FakePrefStore()
        try store.set(JIHapticsPrefs.enabledKey, false)
        try store.set(JIHapticsPrefs.intensityKey, 40)
        let d = dispatcher()
        #expect(d.prefs == .default)
        HapticsPrefsStore.warm(from: store, into: d)
        #expect(d.prefs == JIHapticsPrefs(enabled: false, intensity: 40))
    }

    @Test func setIntensityZeroClampsAndPersistsOne() throws {
        let store = FakePrefStore()
        let d = dispatcher()
        try HapticsPrefsStore.setIntensity(0, store: store, dispatcher: d)
        #expect(d.prefs.intensity == 1)
        #expect(try store.get(JIHapticsPrefs.intensityKey, as: Int.self) == 1)
        #expect(HapticsPrefsStore.load(from: store).intensity == 1)
    }

    @Test func corruptStoreReadsAsDefaults() {
        let d = dispatcher()
        d.prefs = JIHapticsPrefs(enabled: false, intensity: 7)
        HapticsPrefsStore.warm(from: FakePrefStore(corrupt: true), into: d)
        #expect(d.prefs == .default)
    }
}
