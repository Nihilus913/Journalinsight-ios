import Foundation
import Observation
import os
import JIPersistence
#if canImport(HealthKit)
import JIHealthKit
#endif

// B-24 P2: opt-in, one-way mirror of the Mind check-in's MOOD into Apple Health (State of Mind,
// daily mood). Off by default, forward-only (no backfill), mood only: the payload type below has
// no field for the note, stress, energy or dosed — the ADHD-med signal stays sealed on device.

/// Exactly what may leave the sealed store: the day, the mood's valence, the save time.
public nonisolated struct MoodMirrorPayload: Sendable, Equatable {
    public var date: String
    public var valence: Double
    public var updatedAt: Date

    public init(date: String, valence: Double, updatedAt: Date) {
        self.date = date
        self.valence = valence
        self.updatedAt = updatedAt
    }
}

/// nil when the check-in has no mood (open question 4 default: skip the write).
public nonisolated func moodMirrorPayload(_ n: NewCheckIn, savedAt: Date) -> MoodMirrorPayload? {
    guard let mood = n.mood else { return nil }
    return MoodMirrorPayload(date: n.date, valence: mood.valence, updatedAt: savedAt)
}

/// The seam `MindViewModel` and the Settings toggle talk to (fakes in tests, HealthKit in the app).
public protocol MoodMirroring: Sendable {
    /// Asks for State of Mind write access; returns false when sharing is denied.
    func requestAuthorization() async throws -> Bool
    func mirror(_ payload: MoodMirrorPayload) async throws
}

/// The UserDefaults-backed toggle ("Mirror mood to Apple Health"), off unless set.
public nonisolated enum MoodMirrorPrefs {
    public static let key = "ji.mind.mirrorMoodToHealth"
    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
    public static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: key) }
}

nonisolated let moodMirrorLog = Logger(subsystem: "com.journalinsight", category: "mood-mirror")

#if canImport(HealthKit)
/// App implementation: `StateOfMindWriter` (B-24 P1) over the real HealthKit store.
public nonisolated struct HealthKitMoodMirror: MoodMirroring {
    private let writer: StateOfMindWriter<RealHealthStore>

    public init(store: RealHealthStore = RealHealthStore()) {
        writer = StateOfMindWriter(store: store)
    }

    public func requestAuthorization() async throws -> Bool {
        try await writer.requestAuthorization()
        return !writer.isSharingDenied
    }

    public func mirror(_ payload: MoodMirrorPayload) async throws {
        try await writer.write(MoodMirrorEntry(date: payload.date, valence: payload.valence, updatedAt: payload.updatedAt))
    }
}
#endif

/// Settings › Apple Health › "Mirror mood to Apple Health". Toggling on asks HealthKit for
/// State of Mind write access first; a denial or error leaves the toggle off.
@Observable @MainActor
public final class MoodMirrorSettingsModel {
    public private(set) var enabled: Bool
    public private(set) var denied = false
    public private(set) var errorMessage: String?

    private let mirror: any MoodMirroring
    private let defaults: UserDefaults

    public init(mirror: any MoodMirroring, defaults: UserDefaults = .standard) {
        self.mirror = mirror
        self.defaults = defaults
        self.enabled = MoodMirrorPrefs.isEnabled(defaults)
    }

    public func setEnabled(_ on: Bool) async {
        errorMessage = nil
        guard on else {
            denied = false
            enabled = false
            MoodMirrorPrefs.setEnabled(false, defaults)
            return
        }
        do {
            let granted = try await mirror.requestAuthorization()
            denied = !granted
            enabled = granted
        } catch {
            enabled = false
            errorMessage = "Couldn't ask Apple Health for access — \(error.localizedDescription)"
        }
        MoodMirrorPrefs.setEnabled(enabled, defaults)
    }
}
