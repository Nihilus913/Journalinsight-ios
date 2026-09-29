import Foundation
import JICore
import JIPersistence

/// B-57 W4 — copies the phone's gate settings to the hub so the
/// 05:10 morning_go run uses the user's preset and (optional) cap, and its Garmin zone-drift
/// sentinel the user's zone floors, until B-50 moves the verdict onto the phone. Local-first:
/// `save` writes PrefStore and a persisted pending flag BEFORE any network call; a failed push
/// stays pending and `pushIfPending` (app foreground) retries with the latest local value. The
/// hub keeps its previous file until then — it is never reset. Last-write-wins config, so no
/// Outbox queue.
/// W-FIX10 F10-1 (audit 03-F1): the copy is the ONE targets document (`PUT /planning/targets`);
/// the W4 fallback `PUT /planning/gate-settings` (removed hub-side by W-TGT) is gone. Before the
/// §5 import there is no document to send, so the change stays pending.
@MainActor
public final class GateSettingsMirror {
    public static let pendingKey = "gate.settings.hubPending"
    /// GateConfig's words while a change has not reached the hub (Review Focus 3).
    public static let pendingText = "Not on the hub yet"

    private let prefs: PrefStore
    private let store: GateSettingsStore
    private let provider: (any TargetsProviding)?

    public init(prefs: PrefStore, provider: (any TargetsProviding)?) {
        self.prefs = prefs; self.store = GateSettingsStore(prefs: prefs); self.provider = provider
    }

    public var hubPending: Bool { ((try? prefs.get(Self.pendingKey, as: Bool.self)) ?? nil) == true }

    /// "Not on the hub yet" while pending, else nil (nothing to say).
    public var hubStatusText: String? { hubPending ? Self.pendingText : nil }

    @discardableResult
    public func save(_ settings: GateSettings) async -> Bool {
        try? store.save(settings)
        try? prefs.set(Self.pendingKey, true)
        return await pushIfPending()
    }

    @discardableResult
    public func pushIfPending() async -> Bool {
        guard hubPending, let provider, let doc = TargetsStore(prefs: prefs).loadIfPresent() else { return false }
        let s = store.load()
        do {
            _ = try await provider.putTargets(doc)
            // Only clear when nothing newer was saved while the PUT was in flight.
            if store.load() == s { try? prefs.remove(Self.pendingKey) }
            return true
        } catch {
            return false
        }
    }
}
