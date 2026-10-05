import Foundation
import Observation
import JICore
import JIPersistence

/// W-B40 L2 (B-40b-2/-3) — the workout library: the hub's `plan.workout_template` rows (spec §3
/// GET), rendered from `OfflineCache` when the hub is unreachable, with every queued template
/// write (`WorkoutLibraryOutbox`) laid over them so an offline edit shows at once and is marked
/// pending. B-52 p4: Push to Garmin is queued too (outbox kind `garmin_push`, the hub pushes when
/// it gets the row); Import stays hub-only — disabled offline with a reason, never queued (card Q2).
///
/// X-1 (exit-plan change 1): loading NEVER writes. The only writes this model sends are rows the
/// user queued (save / delete) — a cold cache, an empty first launch or an empty hub answer can
/// never push a library over the hub's templates.
@MainActor
@Observable
public final class WorkoutLibraryViewModel {
    public enum LoadState: Equatable, Sendable { case idle, loading, loaded, failed(String) }

    public enum SportFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All", running = "Running", strengthRun = "Strength + Run"
        public var id: String { rawValue }
    }

    public struct Notice: Equatable, Sendable {
        public let text: String
        public let isError: Bool
    }

    public enum SaveResult: Equatable, Sendable {
        /// The hub has it.
        case saved
        /// On this phone, queued for the hub.
        case queued
        /// Refused (hub 4xx / X-1 guard) — the hub's own words; nothing changed.
        case refused(String)
    }

    public nonisolated static let cacheKey = "workouts.templates"

    public private(set) var templates: [WorkoutTemplate] = []
    public private(set) var state: LoadState = .idle
    /// false once a read failed on the network; flips back on the next successful read.
    public private(set) var hubReachable = true
    public private(set) var fetchedAt: Date?
    /// Templates with a queued (not yet delivered) write — the library marks them.
    public private(set) var pendingTemplateIds: Set<Int> = []
    public private(set) var busyGarminIds: Set<Int> = []
    /// B-52 p4: templates with a queued (not yet delivered) push to Garmin.
    public private(set) var pendingPushIds: Set<Int> = []
    public private(set) var isImporting = false
    public private(set) var lastImport: GarminImportReport?
    public var notice: Notice?
    public var filter: SportFilter = .all

    private let provider: any WorkoutLibraryProviding
    private let cache: OfflineCache?
    private let queue: WorkoutLibraryOutbox?
    /// B-52 p4: the `garmin_push` queue (the app's outbox; an in-memory one for fixtures) and the
    /// in-tap drainer that only knows that kind over THIS model's provider.
    private let pushOutbox: Outbox?
    private let pushDrainer: OutboxDrainer?
    private let now: () -> Date
    /// The hub's (or the cached hub's) rows — never the overlay; this is what the cache holds.
    private var base: [WorkoutTemplate] = []
    /// Negative display id of a phone-only template → its queued create's `localId`.
    private var localIds: [Int: String] = [:]

    public init(provider: any WorkoutLibraryProviding, cache: OfflineCache?, outbox: Outbox?, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.cache = cache
        self.queue = outbox.map { WorkoutLibraryOutbox(outbox: $0, provider: provider) }
        self.now = now
        (pushOutbox, pushDrainer) = Self.pushQueue(outbox, provider: provider)
    }

    private static func pushQueue(_ outbox: Outbox?, provider: any WorkoutLibraryProviding) -> (Outbox?, OutboxDrainer?) {
        let box = outbox ?? (try? AppDatabase.inMemory()).map { Outbox(db: $0) }
        let handler = B52WriteKinds.garminPushHandler(provider: { provider })
        return (box, box.map { B52WriteKinds.localDrainer(outbox: $0, handler: handler) })
    }

    /// Fixture screens (previews, the sweep): rows given, no hub, no queue.
    public init(seeded: [WorkoutTemplate], provider: (any WorkoutLibraryProviding)? = nil, hubReachable: Bool = true) {
        let source = provider ?? SeededWorkoutProvider(rows: seeded)
        self.provider = source; self.cache = nil; self.queue = nil; self.now = Date.init
        (pushOutbox, pushDrainer) = Self.pushQueue(nil, provider: source)
        self.base = seeded; self.templates = seeded; self.state = .loaded; self.hubReachable = hubReachable
    }

    // MARK: derived

    public var visibleTemplates: [WorkoutTemplate] {
        switch filter {
        case .all: templates
        case .running: templates.filter { !$0.hasStrength }
        case .strengthRun: templates.filter(\.hasStrength)
        }
    }

    /// "8 workouts · 4 on Garmin Connect" — counts of what is actually listed, never a zero for
    /// a library that has not loaded.
    public var summaryLine: String? {
        // W-FIX11 H1-20: what is listed under the filter — "1 of 4 workouts", nil when none is
        // (the list says "None in this filter."), never the whole library over an empty list.
        let shown = visibleTemplates
        guard !shown.isEmpty else { return nil }
        let onGarmin = shown.filter { $0.garmin != nil }.count
        let n = shown.count, total = templates.count
        let count = filter == .all || n == total ? "\(n) workout\(n == 1 ? "" : "s")" : "\(n) of \(total) workouts"
        return count + (onGarmin > 0 ? " · \(onGarmin) on Garmin Connect" : "")
    }

    /// Why Import is disabled right now (nil = enabled). Import needs the hub by nature (card Q2).
    public var garminDisabledReason: String? {
        hubReachable ? nil : "Offline — Import from Garmin needs the hub."
    }

    /// B-52 p4: Push works offline (it is queued), so only an unsynced template edit — or a push
    /// already queued for it — blocks it: the hub must hold the version that gets pushed.
    public func pushDisabledReason(for template: WorkoutTemplate) -> String? {
        if template.templateId < 0 || pendingTemplateIds.contains(template.templateId) { return "Your edit is still syncing to the hub." }
        if pendingPushIds.contains(template.templateId) { return "Push queued — it goes to Garmin when the hub is reachable." }
        return nil
    }

    public var exerciseOptions: [ExerciseOption] { WorkoutExerciseCatalogue.options(from: templates) }

    // MARK: load

    public func load() async {
        if templates.isEmpty, let hit = try? cache?.get(Self.cacheKey, as: [WorkoutTemplate].self) {
            base = hit.value; fetchedAt = hit.fetchedAt
        }
        applyOverlay()
        if state != .loaded { state = .loading }
        if let queue { _ = await queue.drainOnce() }
        await refresh()
    }

    /// Re-read the hub (no writes).
    public func refresh() async {
        do {
            let rows = try await provider.workoutTemplates()
            base = rows
            hubReachable = true
            fetchedAt = now()
            try? cache?.put(Self.cacheKey, rows)
            state = .loaded
        } catch {
            if case HubError.network = error { hubReachable = false }
            if base.isEmpty && fetchedAt == nil {
                state = .failed(WorkoutLibraryOutbox.describe(error))
            } else {
                state = .loaded   // the cached library stays on screen, marked stale
            }
        }
        applyOverlay()
    }

    // MARK: writes (offline-first)

    public func save(_ draft: WorkoutTemplateDraft, editing: WorkoutTemplate?) async -> SaveResult {
        let write: WorkoutTemplateWrite
        switch editing {
        case nil: write = .create(draft)
        case let t? where t.templateId < 0: write = .updateLocal(localIds[t.templateId] ?? UUID().uuidString, draft)
        case let t?: write = .update(t.templateId, draft)
        }
        return await submit(write)
    }

    public func delete(_ template: WorkoutTemplate) async -> SaveResult {
        if template.templateId < 0, let local = localIds[template.templateId] {
            return await submit(.deleteLocal(local))
        }
        return await submit(.delete(template.templateId))
    }

    private func submit(_ write: WorkoutTemplateWrite) async -> SaveResult {
        guard let queue else { return await sendDirect(write) }
        guard let row = queue.enqueue(write) else {
            return .refused("Couldn't save on this phone — nothing was changed.")
        }
        applyOverlay()
        // Coalesced away (e.g. deleting a template that never reached the hub): nothing to send.
        guard queue.pending().contains(where: { $0.row == row }) else { return .saved }
        let results = await queue.drainOnce()
        let outcome = results[row]
        if results.values.contains(where: { if case .delivered = $0 { true } else { false } }) {
            await refresh()
        } else {
            applyOverlay()
        }
        switch outcome {
        case .refused(let why)?:
            notice = Notice(text: why, isError: true)
            return .refused(why)
        case .delivered?: return .saved
        case .queued?, nil:
            hubReachable = false
            notice = Notice(text: "Saved on this phone — it syncs when the hub is reachable.", isError: false)
            return .queued
        }
    }

    /// No queue wired (fixtures): the direct call is all there is.
    private func sendDirect(_ write: WorkoutTemplateWrite) async -> SaveResult {
        do {
            switch write.op {
            case .create: _ = try await provider.createWorkoutTemplate(write.draft!)
            case .update: _ = try await provider.updateWorkoutTemplate(id: write.templateId ?? 0, write.draft!)
            case .delete: try await provider.deleteWorkoutTemplate(id: write.templateId ?? 0)
            }
            await refresh()
            return .saved
        } catch {
            let why = WorkoutLibraryOutbox.describe(error)
            notice = Notice(text: why, isError: true)
            return .refused(why)
        }
    }

    // MARK: hub-only Garmin actions

    /// B-52 p4: queued first (outbox kind `garmin_push`), then one in-tap attempt. Offline the
    /// row waits and the template is marked "Push queued"; the hub pushes when it gets it.
    public func pushToGarmin(_ template: WorkoutTemplate) async {
        if let reason = pushDisabledReason(for: template) { notice = Notice(text: reason, isError: true); return }
        guard let pushOutbox else { notice = Notice(text: "Couldn't save the push on this phone.", isError: true); return }
        busyGarminIds.insert(template.templateId)
        defer { busyGarminIds.remove(template.templateId) }
        let outcome = await OutboxFirst(outbox: pushOutbox, drainer: pushDrainer)
            .submit(kind: B52WriteKinds.garminPush, payload: GarminPushWrite(templateId: template.templateId))
        applyOverlay()
        switch outcome {
        case .delivered:
            notice = Notice(text: "\(template.name) is on Garmin Connect.", isError: false)
            await refresh()
        case .queued(let reason):
            let offline = reason == WorkoutLibraryViewModel.describeGarmin(HubError.network(""))
                || reason == OutboxFirstError.noProvider(B52WriteKinds.garminPush).message
            if offline { hubReachable = false }
            notice = Notice(text: offline ? "Push queued — \(template.name) goes to Garmin when the hub is reachable."
                                          : "Push queued — \(reason)", isError: !offline)
        case .rejected(let reason), .notQueued(let reason):
            notice = Notice(text: reason, isError: true)
        }
    }

    @discardableResult
    public func importFromGarmin() async -> GarminImportReport? {
        if let reason = garminDisabledReason { notice = Notice(text: reason, isError: true); return nil }
        isImporting = true
        defer { isImporting = false }
        do {
            let report = try await provider.importWorkoutsFromGarmin()
            lastImport = report
            await refresh()
            return report
        } catch {
            if case HubError.network = error { hubReachable = false }
            notice = Notice(text: Self.describeGarmin(error), isError: true)
            return nil
        }
    }

    /// 503 carries the hub's own "Garmin session expired — re-auth on the mini" verbatim.
    public nonisolated static func describeGarmin(_ error: Error) -> String {
        switch error as? HubError {
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .network: "Couldn't reach the hub — Garmin actions need it."
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: "Garmin Connect didn't answer — try again."
        }
    }

    // MARK: overlay

    private func applyOverlay() {
        pendingPushIds = Set(B52WriteKinds.allPending(B52WriteKinds.garminPush, in: pushOutbox, as: GarminPushWrite.self).map(\.templateId))
        guard let queue else { templates = base; return }
        var rows = base
        var pending = Set<Int>()
        localIds = [:]
        let stamp = now().ISO8601Format()
        for (row, write) in queue.pending() {
            switch write.op {
            case .create:
                guard let draft = write.draft else { continue }
                let id = -Int(row)
                localIds[id] = write.localId
                rows.append(draft.previewTemplate(id: id, updatedAt: stamp))
                pending.insert(id)
            case .update:
                guard let id = write.templateId, let draft = write.draft, let i = rows.firstIndex(where: { $0.templateId == id }) else { continue }
                rows[i] = draft.previewTemplate(id: id, basedOn: rows[i], updatedAt: stamp)
                pending.insert(id)
            case .delete:
                rows.removeAll { $0.templateId == write.templateId }
            }
        }
        templates = rows
        pendingTemplateIds = pending
    }
}

/// Fixture screens: serves the seeded rows on read, echoes writes, empty Garmin report.
nonisolated struct SeededWorkoutProvider: WorkoutLibraryProviding {
    let rows: [WorkoutTemplate]
    func workoutTemplates() async throws -> [WorkoutTemplate] { rows }
    func createWorkoutTemplate(_ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate { d.previewTemplate(id: 1000, updatedAt: "") }
    func updateWorkoutTemplate(id: Int, _ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate { d.previewTemplate(id: id, updatedAt: "") }
    func deleteWorkoutTemplate(id: Int) async throws {}
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult { GarminPushResult(garminWorkoutId: nil) }
    func importWorkoutsFromGarmin() async throws -> GarminImportReport {
        GarminImportReport(linked: ImportBucket(count: 0), created: ImportBucket(count: 0), skipped: ImportBucket(count: 0))
    }
}
