import Foundation
import Observation
import JICore
import JICompute
import JIPersistence

// W5b-L3 (P-gate-config). State for `GateConfigView`, the port of RN `app/gate-config.tsx`.
//
// Three blocks, in RN's order:
//  1. LOCAL morning-gate threshold overrides (persisted in `PrefStore` under RN's own key) and the
//     fixture-evaluation preview that runs the REAL `JICompute.evaluate()` — `GateConfigPreview`.
//  2. LOCAL KPI-rule overrides on `JICompute.defaultKpiRules` (same store, RN's key).
//  3. LIVE server KPI targets: `GET/PUT /api/v1/planning/kpi-targets` through the EXISTING
//     `KpiTargetsProviding` (W3b-L2) — optimistic edit, PUT, server row written back verbatim on
//     success, exact rollback + "Couldn't save — reverted." on failure (RN `useUpdateKpiTarget`).
//
// Every stepper tap reads the CURRENT model value rather than a captured one, which is the Swift
// shape of RN's functional `setState` updaters: rapid taps accumulate instead of overwriting.
@Observable @MainActor
public final class GateConfigViewModel {
    public enum ServerPhase: Equatable, Sendable { case idle, loading, loaded, error(String) }

    /// `config_overrides.morning_gate` / `config_overrides.kpi_rules` — RN `localPrefs` keys.
    public static let morningOverridesKey = "config_overrides.morning_gate"
    public static let kpiOverridesKey = "config_overrides.kpi_rules"

    // MARK: Local overrides

    public private(set) var morningOverrides = MorningGateOverrides()
    public private(set) var kpiOverrides = KpiRuleOverrides()
    /// RN `loaded` — false until both local blobs have been read once.
    public private(set) var loaded = false

    // MARK: Server KPI targets

    public private(set) var serverTargets: [KpiTarget] = []
    public private(set) var serverPhase: ServerPhase = .idle
    /// RN `updateServerTarget.isError` → "Couldn't save — reverted." Cleared on the next save.
    public private(set) var serverSaveError: String?

    private let targetsProvider: (any KpiTargetsProviding)?
    private let prefStore: PrefStore

    /// `targetsProvider` is optional so the screen still works with no hub connection saved: the
    /// two local blocks and the preview never need the network; the server block explains itself.
    public init(targetsProvider: (any KpiTargetsProviding)?, prefStore: PrefStore) {
        self.targetsProvider = targetsProvider
        self.prefStore = prefStore
    }

    public var hasServerProvider: Bool { targetsProvider != nil }

    // MARK: - Load

    public func load() async {
        loadLocal()
        await loadServer()
    }

    public func loadLocal() {
        let morning: MorningGateOverrides?? = try? prefStore.get(Self.morningOverridesKey, as: MorningGateOverrides.self)
        morningOverrides = (morning ?? nil) ?? MorningGateOverrides()
        let kpi: KpiRuleOverrides?? = try? prefStore.get(Self.kpiOverridesKey, as: KpiRuleOverrides.self)
        kpiOverrides = (kpi ?? nil) ?? KpiRuleOverrides()
        loaded = true
    }

    public func loadServer() async {
        guard let targetsProvider else { serverPhase = .idle; return }
        serverPhase = .loading
        do {
            serverTargets = try await targetsProvider.kpiTargets()
            serverPhase = .loaded
        } catch {
            if Task.isCancelled { serverPhase = .idle; return }
            serverPhase = .error(Self.describe(error))
        }
    }

    // MARK: - Morning-gate overrides

    public var effectiveConfig: MorningGateConfig { applyMorningGateOverrides(morningOverrides) }

    public func value(for field: MorningGateOverridableField) -> Double {
        morningOverrides[field] ?? field.value(in: .default)
    }

    public func isOverridden(_ field: MorningGateOverridableField) -> Bool { morningOverrides.contains(field) }

    /// RN `bumpMorningField(field, ±meta.step)`: clamps to the field's floor, persists, notifies.
    public func bump(_ field: MorningGateOverridableField, direction: Int) {
        let delta = field.step * Double(direction.signum())
        var next = value(for: field) + delta
        if let floor = field.minimum { next = max(floor, next) }
        // Keep the stored number free of binary-float noise (6.0 + 0.5 + 0.5 … stays 7.0).
        next = (next * 1000).rounded() / 1000
        morningOverrides = morningOverrides.setting(field, to: next)
        persistMorning()
    }

    /// RN `resetMorningField` — clears ONE field back to `MorningGateConfig.default`.
    public func reset(_ field: MorningGateOverridableField) {
        guard morningOverrides.contains(field) else { return }
        morningOverrides = morningOverrides.clearing(field)
        persistMorning()
    }

    /// Card exit criterion: "defaults reset restores `DEFAULT_MORNING_GATE_CONFIG`" — every field.
    public func resetAllMorning() {
        guard !morningOverrides.isEmpty else { return }
        morningOverrides = MorningGateOverrides()
        persistMorning()
    }

    private func persistMorning() {
        if morningOverrides.isEmpty {
            try? prefStore.remove(Self.morningOverridesKey)
        } else {
            try? prefStore.set(Self.morningOverridesKey, morningOverrides)
        }
    }

    // MARK: - Fixture preview

    /// RN `baseline` — fixed, no overrides. The fixture day is a compile-time constant, so the
    /// `throws` on `previewMorningGateVerdict` cannot fire here; the fallback keeps the type honest.
    public static let baselinePreview: GatePreviewResult =
        (try? previewMorningGateVerdict(MorningGateOverrides())) ?? GatePreviewResult(verdict: "", conditions: [])

    /// RN `withOverrides` — recomputed on every edit.
    public var previewWithOverrides: GatePreviewResult {
        (try? previewMorningGateVerdict(morningOverrides)) ?? Self.baselinePreview
    }

    public var verdictFlipped: Bool { previewWithOverrides.verdict != Self.baselinePreview.verdict }

    // MARK: - KPI rule overrides (local)

    public var previewKpiRules: [KpiRule] { applyKpiRuleOverrides(kpiOverrides) }

    public func isKpiOverridden(_ key: String) -> Bool { kpiOverrides.contains(key) }

    /// The effective threshold for one seeded rule. `defaultKpiRules` never carries a nil
    /// `threshold` (only `thresholdHi` can be nil); the 0 fallback mirrors RN's.
    public func kpiThreshold(for rule: KpiRule) -> Double {
        previewKpiRules.first { kpiRuleKey($0) == kpiRuleKey(rule) }?.threshold ?? rule.threshold ?? 0
    }

    /// RN `bumpKpiThreshold(key, base, ±step)`.
    public func bumpKpi(_ rule: KpiRule, direction: Int) {
        let key = kpiRuleKey(rule)
        let current = kpiOverrides[key]?.threshold ?? rule.threshold ?? 0
        let next = ((current + kpiRuleStep(metric: rule.metric) * Double(direction.signum())) * 1000).rounded() / 1000
        kpiOverrides = kpiOverrides.setting(key, threshold: next)
        persistKpi()
    }

    public func resetKpi(_ key: String) {
        guard kpiOverrides.contains(key) else { return }
        kpiOverrides = kpiOverrides.clearing(key)
        persistKpi()
    }

    private func persistKpi() {
        if kpiOverrides.values.isEmpty {
            try? prefStore.remove(Self.kpiOverridesKey)
        } else {
            try? prefStore.set(Self.kpiOverridesKey, kpiOverrides)
        }
    }

    // MARK: - Server KPI targets (live)

    /// RN `nudgeServerTarget`: `Math.round((current + dir * step) * 100) / 100`, optimistic write,
    /// PUT `{threshold}` (the row's own `thresholdHi`/`description` are re-sent so the server's
    /// merge is a no-op on them), server row written back verbatim on success, exact rollback on
    /// failure.
    public func nudgeServer(_ target: KpiTarget, direction: Int) async {
        guard let targetsProvider, let index = serverTargets.firstIndex(where: { $0.targetId == target.targetId }) else { return }
        let previous = serverTargets[index]
        let step = kpiRuleStep(metric: previous.metric)
        let next = ((previous.threshold + step * Double(direction.signum())) * 100).rounded() / 100
        serverSaveError = nil
        serverTargets[index].threshold = next
        do {
            let saved = try await targetsProvider.updateKpiTarget(
                id: previous.targetId, threshold: next, thresholdHi: previous.thresholdHi, description: previous.description
            )
            if let i = serverTargets.firstIndex(where: { $0.targetId == saved.targetId }) { serverTargets[i] = saved }
        } catch {
            if let i = serverTargets.firstIndex(where: { $0.targetId == previous.targetId }) { serverTargets[i] = previous }
            serverSaveError = Self.describeSave(error)
        }
    }

    // MARK: - Copy

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }

    /// RN shows a fixed "Couldn't save — reverted." line; the hub's `detail` is appended verbatim
    /// when it has one (rule 4: named hub errors are UI contracts, never swallowed).
    static func describeSave(_ error: Error) -> String {
        let base = "Couldn't save — reverted."
        switch error as? HubError {
        case .some(.http(_, let detail?)) where !detail.isEmpty: return "\(base) \(detail)"
        case .some(.yazioAuthExpired(let detail)) where !detail.isEmpty: return "\(base) \(detail)"
        case .some(.duplicate(let detail)) where !detail.isEmpty: return "\(base) \(detail)"
        case .some(.unauthorized): return "\(base) Hub rejected the token."
        default: return base
        }
    }
}

// MARK: - B-33 §8.5 fixture

public extension GateConfigViewModel {
    /// The local-override editor over an empty in-memory `PrefStore`, for `ScreenRegistry`/the
    /// screenshot sweep. `nil` only when an in-memory SQLite file cannot be opened.
    static func fixture() -> GateConfigViewModel? {
        guard let prefs = NativeFixtureStore.prefs else { return nil }
        let model = GateConfigViewModel(targetsProvider: nil, prefStore: prefs)
        model.loadLocal()
        return model
    }
}
