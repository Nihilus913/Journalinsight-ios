import Foundation
import Testing

/// B-52 p1 (d): the "no direct send" lint. Every hub WRITE must go through the outbox (enqueue
/// first, drainer replays) — a screen that calls a hub write method directly needs the hub up.
///
/// Two layers, both scanned from source (so a new write path cannot land unseen):
/// 1. Transport: `client.send(` / `client.post(` / `client.delete(` / `hub.post(` only inside the
///    JIHub provider files + the allowlisted transport owners below.
/// 2. Feature: every JIHub method whose body performs one of those writes is discovered
///    automatically; each call site of it outside JIHub must be an outbox replay file
///    (`replayFiles`) or a reviewed `(file, method)` pair in `allowlist` with its reason.
///
/// The allowlist is EXACT both ways: a new direct call fails, and an entry that no longer matches
/// fails too (so B-52 p4 must shrink the list as it moves a write onto the outbox).
///
/// B-52 p4: the "p4 gaps" section is EMPTY — `setTrainingBreak` (kind `training_break`) and
/// `pushWorkoutTemplateToGarmin` (kind `garmin_push`) are only called from `OutboxFirstHandlers`.
/// `importWorkoutsFromGarmin` is not a queued write but a hub command (card Q2): it lives in
/// `hubOnly`, whose files must gate the call on the hub being reachable.
@Suite struct B52NoDirectSendLintTests {
    /// The JournalInsight repo root (this file is Packages/JIFeatures/Tests/JIFeaturesTests/…).
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Files whose job IS replaying queued rows against the hub.
    static let replayFiles: Set<String> = [
        "Packages/JIFeatures/Sources/JIFeatures/Shared/OutboxDrainer.swift",
        "Packages/JIFeatures/Sources/JIFeatures/Shared/OutboxFirst.swift",
        "Packages/JIFeatures/Sources/JIFeatures/Shared/OutboxFirstHandlers.swift",
        "Packages/JIFeatures/Sources/JIFeatures/Training/StrengthOutbox.swift",
        "Packages/JIFeatures/Sources/JIFeatures/Workouts/WorkoutLibraryOutbox.swift",
    ]

    /// Reviewed direct calls, "file|method" → why it may stay (or which B-52 part removes it).
    static let allowlist: [String: String] = [
        // Offline-safe already (card "State today"): enqueue-first; this is the in-tap attempt or
        // the no-outbox (preview/mock) branch.
        "Packages/JIFeatures/Sources/JIFeatures/Today/GateRespondCard.swift|respondGate": "gate respond: outbox-first, in-tap attempt",
        "Packages/JIFeatures/Sources/JIFeatures/Today/GateRespondCard.swift|logFeel": "feel: outbox-first, in-tap attempt",
        "Packages/JIFeatures/Sources/JIFeatures/Today/VerdictOverrideViewModel.swift|setVerdictOverride": "verdict override: outbox-first",
        "Packages/JIFeatures/Sources/JIFeatures/Today/VerdictOverrideViewModel.swift|clearVerdictOverride": "verdict override undo: outbox-first",
        "Packages/JIFeatures/Sources/JIFeatures/Training/TrainingViewModel.swift|updateExercise": "exercise_patch: outbox-first (B-54)",
        "Packages/JIFeatures/Sources/JIFeatures/Training/TrainingViewModel.swift|updatePlanSessionWeekday": "plan_weekday: outbox-first",
        // Name clash, not a hub call: `model.updateExercise` is TrainingViewModel's outbox-first path.
        "Packages/JIFeatures/Sources/JIFeatures/Training/TrainingView.swift|updateExercise": "calls TrainingViewModel.updateExercise (exercise_patch, B-54)",
        "Packages/JIFeatures/Sources/JIFeatures/Workouts/WorkoutLibraryViewModel.swift|createWorkoutTemplate": "no-outbox branch; outbox path = WorkoutLibraryOutbox",
        "Packages/JIFeatures/Sources/JIFeatures/Workouts/WorkoutLibraryViewModel.swift|updateWorkoutTemplate": "no-outbox branch; outbox path = WorkoutLibraryOutbox",
        "Packages/JIFeatures/Sources/JIFeatures/Workouts/WorkoutLibraryViewModel.swift|deleteWorkoutTemplate": "no-outbox branch; outbox path = WorkoutLibraryOutbox",
        "Packages/JIFeatures/Sources/JIFeatures/Safety/GateSettingsMirror.swift|putTargets": "pending-flag mirror, pushed on foreground (B-57 W4)",
        "App/Notifications/ApnsRegistration.swift|registerPushToken": "retry-on-launch (W-B54 B54-2)",
    ]

    /// Hub commands that by nature need the hub (nothing to queue): "file|method" → reason. The
    /// file must disable the action offline with a reason (`offlineGate` must appear in it).
    static let hubOnly: [String: (reason: String, offlineGate: String)] = [
        "Packages/JIFeatures/Sources/JIFeatures/Workouts/WorkoutLibraryViewModel.swift|importWorkoutsFromGarmin":
            ("Garmin import runs on the hub (card Q2): disabled offline", "if let reason = garminDisabledReason"),
    ]

    /// B-52 p4: writes moved onto OutboxFirst — callable ONLY from replay files.
    static let p4Kinds = ["setTrainingBreak", "pushWorkoutTemplateToGarmin"]

    /// Transport owners allowed to call the HubClient write primitives outside JIHub providers.
    static let transportAllowlist: Set<String> = [
        "App/AppEnvironment.swift",                                        // POST ingestion/sync: a hub command, nothing to queue
        "Packages/JIHealthKit/Sources/JIHealthKit/HealthKitUploader.swift", // HK upload: re-reads HealthKit by anchor, own retry
    ]

    static let scanDirs = ["App", "Packages", "WatchApp", "Widgets"]

    static func sources() throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        let fm = FileManager.default
        for dir in scanDirs {
            let base = root.appending(path: dir)
            guard let e = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "swift" {
                let rel = String(url.path.dropFirst(root.path.count + 1))
                if rel.contains("/Tests/") || rel.hasPrefix("AppTests") || rel.contains("/.build/") || rel.hasPrefix("legacy/") { continue }
                out.append((rel, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out
    }

    static var writePrimitive: Regex<(Substring, Substring, Substring)> { /(client|hub)\.(send|post|delete)\(/ }

    /// JIHub methods whose body performs a write (nearest preceding `func name` of a write line).
    static func hubWriteMethods(_ files: [(path: String, text: String)]) -> Set<String> {
        var names = Set<String>()
        for f in files where f.path.hasPrefix("Packages/JIHub/Sources/") {
            var current: String?
            for line in f.text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("///") { continue }
                if let m = line.firstMatch(of: /func (\w+)\s*[(<]/) { current = String(m.1) }
                if line.contains(writePrimitive), let current { names.insert(current) }
            }
        }
        return names
    }

    @Test func transportWritesStayInsideJIHubProviders() throws {
        let files = try Self.sources()
        #expect(files.count > 100, "scan found no sources under \(Self.root.path)")
        var offenders: [String] = []
        for f in files where !f.path.hasPrefix("Packages/JIHub/Sources/") && !Self.transportAllowlist.contains(f.path) {
            for line in f.text.split(separator: "\n") where line.contains(Self.writePrimitive)
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                offenders.append("\(f.path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "direct hub write outside JIHub — route it through OutboxFirst:\n\(offenders.joined(separator: "\n"))")
    }

    @Test func everyHubWriteCallSiteIsOutboxOrReviewed() throws {
        let files = try Self.sources()
        let methods = Self.hubWriteMethods(files)
        #expect(methods.contains("setTrainingBreak") && methods.contains("logWeighin"), "write-method discovery broke: \(methods.sorted())")
        var seen = Set<String>()
        var offenders: [String] = []
        for f in files where !f.path.hasPrefix("Packages/JIHub/") && !f.path.hasPrefix("Packages/JICore/") {
            for method in methods where f.text.contains(".\(method)(") {
                if Self.replayFiles.contains(f.path) { continue }
                let key = "\(f.path)|\(method)"
                if Self.allowlist[key] != nil || Self.hubOnly[key] != nil { seen.insert(key) } else { offenders.append(key) }
            }
        }
        #expect(offenders.isEmpty, "hub write called directly (needs the hub up) — use OutboxFirst or review into the allowlist:\n\(offenders.sorted().joined(separator: "\n"))")
        let stale = Set(Self.allowlist.keys).union(Self.hubOnly.keys).subtracting(seen)
        #expect(stale.isEmpty, "allowlist entries no longer match a call site — remove them:\n\(stale.sorted().joined(separator: "\n"))")
    }

    @Test func b52p4WritesHaveNoDirectCallSite() throws {
        let files = try Self.sources()
        #expect(Self.allowlist.values.allSatisfy { !$0.contains("B-52 p4") }, "B-52 p4 gap still allowlisted")
        for method in Self.p4Kinds {
            #expect(Self.allowlist.keys.allSatisfy { !$0.hasSuffix("|\(method)") }, "\(method) is allowlisted")
            let sites = files.filter { !$0.path.hasPrefix("Packages/JIHub/") && !$0.path.hasPrefix("Packages/JICore/")
                && $0.text.contains(".\(method)(") }.map(\.path)
            #expect(sites == ["Packages/JIFeatures/Sources/JIFeatures/Shared/OutboxFirstHandlers.swift"],
                    "\(method) must only be replayed from OutboxFirstHandlers: \(sites)")
        }
    }

    @Test func hubOnlyCommandsAreGatedOffline() throws {
        let files = try Self.sources()
        for (key, entry) in Self.hubOnly {
            let path = String(key.split(separator: "|")[0])
            let text = files.first { $0.path == path }?.text ?? ""
            #expect(text.contains(entry.offlineGate), "\(key): no offline gate `\(entry.offlineGate)`")
        }
    }
}
