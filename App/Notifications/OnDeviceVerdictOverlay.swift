import Foundation
import JICore
import JIFeatures
import JIHealthKit
import JIHub
import JIPersistence

/// B-44 Option B (Toby 2026-10-04, "(4) REVISED"): the gate and Decide read the ON-DEVICE verdict
/// from 2026-10-05 — no UI change, no dual display. `HubDataProvider` lays this over its
/// `/planning/morning(-verdict)` answers; the hub keeps computing its own verdict silently (the
/// shadow log and `plan.verdict_compare` keep it). The phone has no verdict for a day (no Apple
/// night yet, HealthKit unavailable, compute error) -> nil, and the hub's verdict stays as the
/// fallback rather than "No verdict yet".
nonisolated struct OnDeviceVerdictOverlay: MorningVerdictOverlay {
    typealias Compute = @Sendable (String) async throws -> OnDeviceVerdictResult?

    /// First morning the on-device verdict drives the gate (B-44 decision (1)); days before it keep
    /// the hub's verdict (history is not rewritten).
    static let startDay = "2026-10-05"
    /// DEBUG only: `-ji.ondevice.overlayFrom yyyy-MM-dd` moves the start (simulator exit check).
    static let startOverrideKey = "ji.ondevice.overlayFrom"
    /// Today's verdict is recomputed at most this often (a late-synced night can still change it).
    static let todayTTL: TimeInterval = 15 * 60

    let startDay: String
    let today: @Sendable () -> String
    let compute: Compute
    /// Each freshly computed result for TODAY (shadow log + upload).
    let onResult: ShadowLogWriter.Write?
    let cache = OverlayCache()

    var todayKey: String { today() }

    func verdict(day: String) async -> OnDeviceMorning? {
        let today = todayKey
        guard day >= startDay, day <= today else { return nil }
        let now = Date()
        if let hit = await cache.get(day, now: now, ttl: day == today ? Self.todayTTL : .infinity) { return hit }
        guard let result = try? await compute(day) else { return nil }
        // Decision (4): no UI change — the hub's verdict vocabulary as is, no calibrating label.
        let morning = OnDeviceMorning(day: day, verdict: result.verdict, reason: result.reason,
                                      sessionPrescription: result.sessionPrescription,
                                      gateSignals: result.signals, computedAt: now.ISO8601Format())
        await cache.put(day, morning, at: now)
        if day == today { await onResult?(day, result, now) }
        return morning
    }

    actor OverlayCache {
        private var entries: [String: (OnDeviceMorning, Date)] = [:]
        func get(_ day: String, now: Date, ttl: TimeInterval) -> OnDeviceMorning? {
            guard let (m, at) = entries[day], now.timeIntervalSince(at) < ttl else { return nil }
            return m
        }
        func put(_ day: String, _ m: OnDeviceMorning, at: Date) {
            entries[day] = (m, at)
            if entries.count > 14, let oldest = entries.keys.min() { entries[oldest] = nil }
        }
    }
}

/// B-44 Option B: each morning's on-device verdict goes to the hub (`plan.ondevice_verdict`)
/// through the `Outbox` — offline-first, replayed by every `OutboxDrainer` built over the hub.
/// One row per (day, verdict, inputs): re-opening the app does not queue the same verdict again.
nonisolated enum OnDeviceVerdictUploadQueue {
    private static let memoryKey = "ji.ondevice.verdict.lastUploaded"

    static func body(day: String, result: OnDeviceVerdictResult, computedAt: Date) -> OnDeviceVerdictUpload {
        OnDeviceVerdictUpload(date: day, verdict: result.verdict, reason: result.reason,
                              sessionPrescription: result.sessionPrescription, baselineNights: result.baselineNights,
                              inputsDigest: result.inputsDigest, computedAt: computedAt.ISO8601Format())
    }

    /// `hub` is read at upload time (the CURRENT connection, after a reconnect too).
    static func make(hub: @escaping @Sendable () async -> HubDataProvider?) -> ShadowLogWriter.Write? {
        guard let db = try? AppDatabase.onDisk() else { return nil }
        let outbox = Outbox(db: db)
        return { day, result, computedAt in
            let key = "\(result.verdict)|\(result.inputsDigest ?? "-")"
            // UserDefaults is thread-safe by documented contract.
            let defaults = UserDefaults.standard
            var map = (defaults.dictionary(forKey: memoryKey) as? [String: String]) ?? [:]
            if map[day] != key {
                guard (try? outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind,
                                           payload: body(day: day, result: result, computedAt: computedAt))) != nil else { return }
                map[day] = key
                let keep = map.keys.sorted().suffix(7)
                defaults.set(map.filter { keep.contains($0.key) }, forKey: memoryKey)
            }
            guard let hub = await hub() else { return }   // stays queued for the app-wide drainer
            await MainActor.run {
                Task { @MainActor in _ = await OutboxDrainer(outbox: outbox, hub: hub).drainOnce() }
            }
        }
    }
}
