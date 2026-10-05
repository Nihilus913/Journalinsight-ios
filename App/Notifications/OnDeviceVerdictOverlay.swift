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
    let startDay: String
    let today: @Sendable () -> String
    let compute: Compute
    /// Each freshly computed result for TODAY (shadow log + upload).
    let onResult: ShadowLogWriter.Write?
    /// RG-12 / B-127: the day's FIRST verdict is frozen (UserDefaults, survives relaunch) — later
    /// overlays never rewrite "YOUR CALL FOR TODAY · HH:mm", the word or the rows.
    var frozen: any FrozenMorningStoring = UserDefaultsFrozenMorningStore()
    var now: @Sendable () -> Date = { Date() }

    var todayKey: String { today() }

    func verdict(day: String) async -> OnDeviceMorning? {
        let today = todayKey
        guard day >= startDay, day <= today else { return nil }
        let at = now()
        var computed: OnDeviceVerdictResult?
        let resolved = await OnDeviceMorningFreeze.resolve(day: day, store: frozen) {
            guard let result = try? await compute(day) else { return nil }
            computed = result
            // Decision (4): no UI change — the hub's verdict vocabulary as is, no calibrating label.
            return OnDeviceMorning(day: day, verdict: result.verdict, reason: result.reason,
                                   sessionPrescription: result.sessionPrescription,
                                   // RG-16: the HRV row names the phone baseline while it calibrates.
                                   gateSignals: OnDeviceVerdictLabel.sourceLabelled(result),
                                   computedAt: at.ISO8601Format())
        }
        guard let resolved else { return nil }
        if resolved.fresh, day == today, let computed { await onResult?(day, computed, at) }
        return resolved.morning
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
