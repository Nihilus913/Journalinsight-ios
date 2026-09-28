import SwiftUI
import Observation
import JICore
import JIPersistence

// W-TGT L3 (P-targets) — the ONE place a screen reads and edits the targets document. The shell
// owns one model, injects it (`\.targetsModel`) and its document (`\.targets`, L1's accessor) at
// the root, outermost, so every sheet (Settings, My KPIs) sees the same numbers. Edits go through
// `TargetsMirror` (local first, outbox kind `targets`); Limits keep their own engine
// (`GateConfigViewModel` → `GateSettingsStore` → the same document) for the cap re-check reminder.

public extension EnvironmentValues {
    /// The editable targets. nil = previews / tests without an editor: screens then show the
    /// numbers read-only and no Edit button (never a tap that does nothing).
    @Entry var targetsModel: TargetsModel? = nil
}

@Observable @MainActor
public final class TargetsModel {
    /// The stored document (`.empty` — no numbers — before the §5 import).
    public private(set) var document: TargetsDocument
    /// A change that has not reached the hub yet ("Not on the hub yet").
    public private(set) var hubPending = false
    /// The last edit's failure in words (nil = none).
    public private(set) var saveError: String?
    /// False until the §5 import (or a first save) wrote the document — readers that fall back to
    /// an older source (the hub's goals document) use `storedDocument`.
    public private(set) var isStored: Bool

    /// The document once it exists on this phone; nil before the import.
    public var storedDocument: TargetsDocument? { isStored ? document : nil }

    private let store: TargetsStore
    private let mirror: TargetsMirror?
    /// Builds the Limits engine (HR cap + re-check reminder, zones, Avoid Zone 5).
    private let makeLimitsModel: (@MainActor () -> GateConfigViewModel)?
    @ObservationIgnored private var limitsModelCache: GateConfigViewModel?
    /// Called after every change (the shell refreshes the energy band, gate settings, widgets).
    private let onChange: (@MainActor (TargetsDocument) -> Void)?

    public init(prefs: PrefStore, mirror: TargetsMirror? = nil,
                makeLimitsModel: (@MainActor () -> GateConfigViewModel)? = nil,
                onChange: (@MainActor (TargetsDocument) -> Void)? = nil) {
        self.store = TargetsStore(prefs: prefs)
        self.mirror = mirror
        self.makeLimitsModel = makeLimitsModel
        self.onChange = onChange
        let stored = TargetsStore(prefs: prefs).loadIfPresent()
        self.document = stored ?? .empty
        self.isStored = stored != nil
        self.hubPending = mirror?.hubPending ?? false
    }

    public var canEditLimits: Bool { makeLimitsModel != nil }

    /// The Limits engine, built once per model (its foreground observer lives with it).
    public var limitsModel: GateConfigViewModel? {
        if let limitsModelCache { return limitsModelCache }
        let m = makeLimitsModel?()
        m?.loadLocal()
        limitsModelCache = m
        return m
    }

    /// Re-reads the stored document (after the launch import, a Limits edit, onboarding).
    public func reload() {
        let stored = store.loadIfPresent()
        if (stored != nil) != isStored { isStored = stored != nil }
        let latest = stored ?? .empty
        if latest != document { document = latest; onChange?(latest) }
        let pending = (mirror?.hubPending ?? false) || (limitsModelCache?.hubPending ?? false)
        if pending != hubPending { hubPending = pending }
    }

    /// Saves an edit (Goals, Rules) locally and mirrors it.
    public func update(_ change: (inout TargetsDocument) -> Void) async {
        var d = store.load()
        change(&d)
        await save(d)
    }

    public func save(_ next: TargetsDocument) async {
        saveError = nil
        if let mirror {
            let outcome = await mirror.save(next)
            hubPending = outcome == .queued
        } else {
            do { try store.save(next) } catch { saveError = "Couldn't save on this phone — try again." }
        }
        let stored = store.loadIfPresent()
        isStored = stored != nil
        let latest = stored ?? .empty
        document = latest
        onChange?(latest)
    }

    /// "Reset rules to recommended": every Rule back to its recommendation (the caution preset
    /// too). Goals and Limits are never reset by the app.
    public func resetRules() async {
        await update { $0.rules = TargetRules() }
    }

    /// Foreground / reachable-again: sends a queued document, then re-reads.
    public func pushIfPending() async {
        await mirror?.pushIfPending()
        await limitsModelCache?.foregroundSync()
        reload()
    }

    // MARK: - Launch (spec §5)

    /// Once per launch, BEFORE anything reads targets: the pre-W4 install migration, then the
    /// one-shot import (verbatim, missing = nil, sleep goal never seeded), which queues the first
    /// mirror. `cache` is the app's OfflineCache (where `kpi.targets` — the hub's rule rows — and
    /// the goals document live), so a rule Toby changed on the hub is carried over, not reset.
    public static func migrateAtLaunch(prefs: PrefStore, cache: OfflineCache?, goals: GoalStore?, outbox: Outbox?,
                                       log: (String) -> Void = { _ in }) {
        GateSettingsStore(prefs: prefs).migratePreW4InstallIfNeeded()
        TargetsStore(prefs: prefs).migrateIfNeeded(.init(cache: cache, goals: goals, outbox: outbox), log: log)
    }

    // MARK: - Fixture

    /// An in-memory model over `document` (sweep / gallery / previews; no mirror, no Limits engine).
    public static func fixture(_ document: TargetsDocument) -> TargetsModel? {
        guard let db = try? AppDatabase.inMemory() else { return nil }
        let prefs = PrefStore(db: db)
        try? TargetsStore(prefs: prefs).save(document)
        return TargetsModel(prefs: prefs)
    }
}
