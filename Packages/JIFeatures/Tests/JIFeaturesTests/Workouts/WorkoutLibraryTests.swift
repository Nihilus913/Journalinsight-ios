import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// A hub that serves the library routes (the shape `HubDataProvider` has), recording every call.
nonisolated final class FakeWorkoutHub: WorkoutLibraryProviding, @unchecked Sendable {
    var rows: [WorkoutTemplate]
    var readsFail = false
    var writeError: Error?
    var garminError: Error?
    var calls: [String] = []
    var lastDraft: WorkoutTemplateDraft?
    private var nextId = 100

    init(rows: [WorkoutTemplate]) { self.rows = rows }

    func workoutTemplates() async throws -> [WorkoutTemplate] {
        calls.append("GET")
        if readsFail { throw HubError.network("offline") }
        return rows
    }
    func createWorkoutTemplate(_ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        calls.append("POST"); lastDraft = draft
        if let writeError { throw writeError }
        nextId += 1
        let t = draft.previewTemplate(id: nextId, updatedAt: "2026-09-28T12:00:00Z")
        rows.append(t)
        return t
    }
    func updateWorkoutTemplate(id: Int, _ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        calls.append("PUT \(id)"); lastDraft = draft
        if let writeError { throw writeError }
        let i = try #require(rows.firstIndex { $0.templateId == id })
        rows[i] = draft.previewTemplate(id: id, basedOn: rows[i], updatedAt: "2026-09-28T12:00:00Z")
        return rows[i]
    }
    func deleteWorkoutTemplate(id: Int) async throws {
        calls.append("DELETE \(id)")
        if let writeError { throw writeError }
        rows.removeAll { $0.templateId == id }
    }
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult {
        calls.append("PUSH \(id)")
        if let garminError { throw garminError }
        return GarminPushResult(garminWorkoutId: 555)
    }
    func importWorkoutsFromGarmin() async throws -> GarminImportReport {
        calls.append("IMPORT")
        if let garminError { throw garminError }
        return GarminImportReport(linked: ImportBucket(count: 1, names: ["Long Run Zone 2"]), created: ImportBucket(count: 2, names: ["Friday", "Drill"]), skipped: ImportBucket(count: 0))
    }
    var writes: [String] { calls.filter { $0 != "GET" } }
}

private func run(_ name: String, id: Int, seconds: Int = 1800, garmin: GarminLink? = nil) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "running", location: .outdoor, weekdays: [], steps: [],
                    updatedAt: "2026-09-28T08:00:00Z",
                    segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: seconds), target: .hrRange(lo: 116, hi: 138)))])],
                    garmin: garmin)
}

private func strengthRun(_ name: String, id: Int) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "running", location: .outdoor, weekdays: [4], steps: [],
                    updatedAt: "2026-09-28T08:00:00Z",
                    segments: [
                        WorkoutSegment(sport: .strength, steps: [.strength(StrengthStep(exerciseKey: "Barbell Row", garminCategory: "ROW", garminExercise: "BARBELL_ROW", sets: 3, reps: 12, weightKg: 50))]),
                        WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 3600), target: .hrZone(2)))]),
                    ])
}

private func draft(_ name: String, seconds: Int = 1200) -> WorkoutTemplateDraft {
    WorkoutTemplateDraft(name: name, activity: "running", location: .outdoor, description: nil,
                         segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: seconds), target: .none))])])
}

@MainActor
private func makeLibrary(_ hub: FakeWorkoutHub, db: AppDatabase? = nil) throws -> (WorkoutLibraryViewModel, OfflineCache, Outbox) {
    let db = try db ?? AppDatabase.inMemory()
    let cache = OfflineCache(db: db)
    let outbox = Outbox(db: db)
    return (WorkoutLibraryViewModel(provider: hub, cache: cache, outbox: outbox), cache, outbox)
}

@MainActor
@Suite struct WorkoutLibraryTests {
    @Test func loadAdoptsTheHubAndCachesIt() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1), strengthRun("Friday", id: 2)])
        let (vm, cache, _) = try makeLibrary(hub)
        await vm.load()
        #expect(vm.templates.map(\.name) == ["Zone 2", "Friday"])
        #expect(vm.state == .loaded && vm.hubReachable)
        #expect(try cache.get(WorkoutLibraryViewModel.cacheKey, as: [WorkoutTemplate].self)?.value.count == 2)
        #expect(vm.summaryLine == "2 workouts")
    }

    // MARK: X-1 (exit-plan change 1, XC half) — an empty local library never overwrites the hub

    @Test func firstLaunchWithAnEmptyLocalLibrarySendsNoWrite() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1), run("Norwegian 4×4", id: 3)])
        let (vm, _, _) = try makeLibrary(hub)   // empty cache, empty queue = first launch
        await vm.load()
        await vm.refresh()
        #expect(hub.writes.isEmpty, "a load / sync never writes: \(hub.writes)")
        #expect(hub.rows.count == 2)
        #expect(vm.templates.count == 2, "the hub's library is adopted, not replaced")
    }

    @Test func anEmptyHubAnswerDoesNotTriggerAPushOfTheCachedLibrary() async throws {
        let db = try AppDatabase.inMemory()
        try OfflineCache(db: db).put(WorkoutLibraryViewModel.cacheKey, [run("Zone 2", id: 1)])
        let hub = FakeWorkoutHub(rows: [])
        let (vm, _, _) = try makeLibrary(hub, db: db)
        await vm.load()
        #expect(hub.writes.isEmpty)
        #expect(vm.templates.isEmpty, "the hub is the truth on read")
    }

    @Test func aSegmentlessSaveIsRefusedAndNeverQueued() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        let db = try AppDatabase.inMemory()
        let outbox = Outbox(db: db)
        let vm = WorkoutLibraryViewModel(provider: SegmentGuardedHub(hub), cache: OfflineCache(db: db), outbox: outbox)
        await vm.load()
        let result = await vm.save(WorkoutTemplateDraft(name: "Zone 2", activity: "running", location: .outdoor, description: nil, segments: []), editing: vm.templates[0])
        guard case .refused = result else { Issue.record("expected refusal, got \(result)"); return }
        #expect(hub.writes.isEmpty)
        #expect(try outbox.pending().isEmpty, "a refused row is retired, never retried")
        #expect(vm.templates[0].segments.count == 1, "the hub template is untouched")
    }

    // MARK: offline-first (B-52)

    @Test func offlineRendersTheCachedLibraryAndDisablesGarminWithAReason() async throws {
        let db = try AppDatabase.inMemory()
        try OfflineCache(db: db).put(WorkoutLibraryViewModel.cacheKey, [run("Zone 2", id: 1)])
        let hub = FakeWorkoutHub(rows: [])
        hub.readsFail = true
        let (vm, _, _) = try makeLibrary(hub, db: db)
        await vm.load()
        #expect(vm.templates.map(\.name) == ["Zone 2"])
        #expect(vm.state == .loaded && !vm.hubReachable)
        #expect(vm.garminDisabledReason != nil)
        await vm.pushToGarmin(vm.templates[0])
        _ = await vm.importFromGarmin()
        #expect(!hub.calls.contains { $0.hasPrefix("PUSH") || $0 == "IMPORT" }, "Garmin actions are never attempted or queued offline")
    }

    @Test func offlineNoCacheIsAnHonestFailureNotAnEmptyLibrary() async throws {
        let hub = FakeWorkoutHub(rows: [])
        hub.readsFail = true
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        guard case .failed = vm.state else { Issue.record("expected failed, got \(vm.state)"); return }
        #expect(vm.summaryLine == nil)
    }

    @Test func offlineSaveQueuesShowsPendingAndDrainsOnReconnect() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        let (vm, _, outbox) = try makeLibrary(hub)
        await vm.load()
        hub.readsFail = true
        hub.writeError = HubError.network("offline")
        let result = await vm.save(draft("Easy 20"), editing: nil)
        #expect(result == .queued)
        #expect(vm.templates.map(\.name) == ["Zone 2", "Easy 20"])
        let local = try #require(vm.templates.last)
        #expect(local.templateId < 0 && vm.pendingTemplateIds.contains(local.templateId))
        #expect(try outbox.pending().count == 1)

        hub.readsFail = false
        hub.writeError = nil
        await vm.load()
        #expect(hub.calls.filter { $0 == "POST" }.count == 2, "one failed attempt, one delivery — never a duplicate create")
        #expect(try outbox.pending().isEmpty)
        #expect(vm.pendingTemplateIds.isEmpty)
        #expect(vm.templates.map(\.name) == ["Zone 2", "Easy 20"])
        #expect(vm.templates.allSatisfy { $0.templateId > 0 })
    }

    @Test func offlineEditsOfOneTemplateReplayAsOnePutWithTheNewestBody() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        hub.writeError = HubError.network("offline")
        _ = await vm.save(draft("Zone 2", seconds: 1500), editing: vm.templates[0])
        _ = await vm.save(draft("Zone 2", seconds: 2100), editing: vm.templates[0])
        hub.writeError = nil
        hub.calls = []
        await vm.load()
        #expect(hub.writes == ["PUT 1"])
        #expect(hub.lastDraft?.segments.first?.steps.first?.cardio?.end == .time(seconds: 2100))
    }

    @Test func createEditDeleteOfflineSendsNothing() async throws {
        let hub = FakeWorkoutHub(rows: [])
        let (vm, _, outbox) = try makeLibrary(hub)
        await vm.load()
        hub.writeError = HubError.network("offline")
        _ = await vm.save(draft("Temp"), editing: nil)
        let local = try #require(vm.templates.first)
        _ = await vm.save(draft("Temp 2"), editing: local)
        #expect(vm.templates.map(\.name) == ["Temp 2"])
        _ = await vm.delete(try #require(vm.templates.first))
        #expect(try vm.templates.isEmpty && outbox.pending().isEmpty)
        hub.writeError = nil
        hub.calls = []
        await vm.load()
        #expect(hub.writes.isEmpty)
    }

    @Test func aHubRefusalRetiresTheRowAndRevertsTheScreen() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        let (vm, _, outbox) = try makeLibrary(hub)
        await vm.load()
        hub.writeError = HubError.http(status: 422, detail: "hi must be <= 175")
        let result = await vm.save(draft("Zone 2", seconds: 999), editing: vm.templates[0])
        #expect(result == .refused("hi must be <= 175"))
        #expect(try outbox.pending().isEmpty)
        #expect(vm.templates[0].segments[0].steps[0].cardio?.end == .time(seconds: 1800))
        #expect(vm.notice?.isError == true)
    }

    @Test func onlineSaveIsDeliveredAndReRead() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        #expect(await vm.save(draft("Zone 2", seconds: 2400), editing: vm.templates[0]) == .saved)
        #expect(hub.writes == ["PUT 1"])
        #expect(vm.templates[0].segments[0].steps[0].cardio?.end == .time(seconds: 2400))
        #expect(vm.pendingTemplateIds.isEmpty)
    }

    // MARK: Garmin (hub-only)

    @Test func pushIsBlockedWhileAnEditIsPendingThenGoesThrough() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1, garmin: GarminLink(workoutId: 9, current: true, pushedAt: nil))])
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        hub.writeError = HubError.network("offline")
        _ = await vm.save(draft("Zone 2", seconds: 2400), editing: vm.templates[0])
        #expect(vm.pushDisabledReason(for: vm.templates[0]) != nil)
        hub.writeError = nil
        await vm.load()
        #expect(vm.pushDisabledReason(for: vm.templates[0]) == nil)
        await vm.pushToGarmin(vm.templates[0])
        #expect(hub.calls.contains("PUSH 1"))
    }

    @Test func garminSessionExpiredShowsTheHubsWords() async throws {
        let hub = FakeWorkoutHub(rows: [run("Zone 2", id: 1)])
        hub.garminError = HubError.http(status: 503, detail: "Garmin session expired — re-auth on the mini")
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        await vm.pushToGarmin(vm.templates[0])
        #expect(vm.notice == .init(text: "Garmin session expired — re-auth on the mini", isError: true))
        #expect(vm.hubReachable, "a 503 from Garmin is not the hub being offline")
    }

    @Test func importReportIsKeptAndTheLibraryReRead() async throws {
        let hub = FakeWorkoutHub(rows: [])
        let (vm, _, _) = try makeLibrary(hub)
        await vm.load()
        let report = try #require(await vm.importFromGarmin())
        #expect(report.created.names == ["Friday", "Drill"])
        #expect(vm.lastImport == report)
        #expect(hub.calls.suffix(2) == ["IMPORT", "GET"])
    }

    @Test func filterSplitsRunningFromStrengthPlusRun() {
        let vm = WorkoutLibraryViewModel(seeded: [run("Zone 2", id: 1), strengthRun("Friday", id: 2)])
        vm.filter = .running
        #expect(vm.visibleTemplates.map(\.name) == ["Zone 2"])
        vm.filter = .strengthRun
        #expect(vm.visibleTemplates.map(\.name) == ["Friday"])
        #expect(vm.exerciseOptions.contains { $0.key == "Barbell Row" })
    }
}

/// Wraps the fake with the REAL provider guard (`HubDataProvider.guardedBody`'s rule) so the VM
/// test sees the refusal a live hub provider would raise.
nonisolated final class SegmentGuardedHub: WorkoutLibraryProviding, @unchecked Sendable {
    let inner: FakeWorkoutHub
    init(_ inner: FakeWorkoutHub) { self.inner = inner }
    func workoutTemplates() async throws -> [WorkoutTemplate] { try await inner.workoutTemplates() }
    func createWorkoutTemplate(_ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        guard !d.segments.isEmpty else { throw WorkoutTemplateWouldClear(templateId: nil) }
        return try await inner.createWorkoutTemplate(d)
    }
    func updateWorkoutTemplate(id: Int, _ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        guard !d.segments.isEmpty else { throw WorkoutTemplateWouldClear(templateId: id) }
        return try await inner.updateWorkoutTemplate(id: id, d)
    }
    func deleteWorkoutTemplate(id: Int) async throws { try await inner.deleteWorkoutTemplate(id: id) }
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult { try await inner.pushWorkoutTemplateToGarmin(id: id) }
    func importWorkoutsFromGarmin() async throws -> GarminImportReport { try await inner.importWorkoutsFromGarmin() }
}

@MainActor
@Suite struct WorkoutEditorTests {
    private func editor(_ t: WorkoutTemplate? = nil) -> WorkoutEditorViewModel {
        WorkoutEditorViewModel(template: t) { _ in .saved }
    }

    @Test func newWorkoutStartsWithOneRunningStepAndNeedsAName() {
        let vm = editor()
        #expect(vm.segments.count == 1 && vm.segments[0].sport == .running && vm.segments[0].steps.count == 1)
        #expect(!vm.canSave && vm.validationIssues.first == "Give the workout a name.")
        vm.name = "Easy"
        #expect(vm.canSave)
    }

    @Test func draftRoundTripsAnExistingTemplate() {
        let t = strengthRun("Friday", id: 2)
        let vm = editor(t)
        #expect(vm.draft == WorkoutTemplateDraft(t))
        #expect(vm.weekdays == [4])
    }

    @Test func hrAbove175IsCaughtBeforeTheHub() throws {
        let vm = editor(run("Z", id: 1))
        let id = vm.segments[0].steps[0].id
        vm.update(id, to: .cardio(CardioStep(purpose: .work, end: .time(seconds: 60), target: .hrRange(lo: 160, hi: 180))))
        #expect(!vm.canSave)
        #expect(vm.validationIssues.contains { $0.contains("175") })
    }

    @Test func intervalRepeatStaysPaired() throws {
        let vm = editor(run("Z", id: 1))
        let seg = vm.segments[0].id
        vm.addCardioStep(to: seg, purpose: .recovery)
        let work = vm.segments[0].steps[0].id
        vm.update(work, to: .cardio(CardioStep(purpose: .work, end: .time(seconds: 240), target: .hrRange(lo: 160, hi: 175), repeat: 4)))
        #expect(vm.segments[0].steps[1].step.cardio?.repeat == 4)
        #expect(vm.validationIssues.isEmpty)
        vm.removeSteps(at: [1], in: seg)
        #expect(vm.validationIssues.contains { $0.contains("repeats need") })
    }

    @Test func strengthStepNeedsRepsOrTime() {
        let vm = editor()
        vm.name = "Lift"
        vm.segments = []
        vm.addSegment(.strength)
        #expect(vm.canSave)
        let id = vm.segments[0].steps[0].id
        var s = try! #require(vm.step(id)?.strength)
        s.reps = nil
        vm.update(id, to: .strength(s))
        #expect(!vm.canSave)
        s.seconds = 45
        vm.update(id, to: .strength(s))
        #expect(vm.canSave)
        #expect(vm.watchDisabledReason != nil, "strength-only has nothing for the Watch")
    }

    @Test func strengthPartTakesOnlyWarmupOrCooldownCardio() {
        let vm = editor()
        vm.name = "Lift"
        vm.segments = []
        vm.addSegment(.strength)
        vm.addCardioStep(to: vm.segments[0].id, purpose: .warmup)
        #expect(vm.canSave)
        vm.addCardioStep(to: vm.segments[0].id, purpose: .work)
        #expect(!vm.canSave)
    }

    @Test func refusalKeepsTheSheetOpenWithTheHubsWords() async {
        let vm = WorkoutEditorViewModel(template: run("Z", id: 1)) { _ in .refused("name already exists") }
        #expect(await vm.save() == false)
        #expect(vm.errorText == "name already exists")
    }

    @Test func clearedDescriptionIsNil() {
        let vm = editor(run("Z", id: 1))
        vm.descriptionText = "   "
        #expect(vm.draft.description == nil)
    }
}

@Suite struct WorkoutFormatTests {
    @Test func cardioSummaryExpandsRepeatsAndSpansBpm() {
        let t = WorkoutTemplate(templateId: 3, name: "Norwegian 4×4", activity: "running", location: .outdoor, weekdays: [0, 4],
                                steps: [
                                    WorkoutStep(purpose: .warmup, seconds: 600, hrLo: 100, hrHi: 140),
                                    WorkoutStep(purpose: .work, seconds: 240, hrLo: 160, hrHi: 175, repeat: 4),
                                    WorkoutStep(purpose: .recovery, seconds: 180, hrLo: 100, hrHi: 140, repeat: 4),
                                    WorkoutStep(purpose: .cooldown, seconds: 300, hrLo: 100, hrHi: 140),
                                ], updatedAt: "x")
        #expect(WorkoutFormat.summary(t) == "43 min · 10 steps · 100–175 bpm")
        #expect(WorkoutFormat.weekdays(t.weekdays) == ["Mon", "Fri"])
    }

    @Test func lapOnlyWorkoutNeverSaysZeroMinutes() {
        let t = WorkoutTemplate(templateId: 1, name: "Drills", activity: "running", location: .outdoor, weekdays: [], steps: [], updatedAt: "x",
                                segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .lap, target: .hrZone(2)))])])
        #expect(WorkoutFormat.summary(t) == "1 step · Zone 2")
    }

    #if canImport(WorkoutKit)
    /// B40-V6: Send to Watch read the compat `steps`, so every segments-only workout (all made in
    /// the app, all Garmin imports) said "0 min · 0 steps".
    @Test @MainActor func sendToWatchSummaryReadsSegments() {
        let t = WorkoutTemplate(templateId: 9, name: "R2 Verify Tempo", activity: "running", location: .outdoor, weekdays: [3], steps: [], updatedAt: "x",
                                segments: [WorkoutSegment(sport: .running, steps: [
                                    .cardio(CardioStep(purpose: .warmup, end: .time(seconds: 600), target: .hrZone(1))),
                                    .cardio(CardioStep(purpose: .work, end: .time(seconds: 1200), target: .hrZone(3))),
                                ])])
        #expect(SendToWatchSheet.summary(t) == WorkoutFormat.summary(t))
        #expect(!SendToWatchSheet.summary(t).hasPrefix("0 min"))
    }
    #endif

    @Test func strengthPlusRunSummary() {
        let t = WorkoutTemplate(templateId: 2, name: "Friday", activity: "running", location: .outdoor, weekdays: [], steps: [], updatedAt: "x",
                                segments: [
                                    WorkoutSegment(sport: .strength, steps: [.strength(StrengthStep(exerciseKey: "Plank", garminCategory: "PLANK", sets: 3, seconds: 45))]),
                                    WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 3600), target: .hrZone(2)))]),
                                ])
        #expect(WorkoutFormat.summary(t) == "Strength · 1 exercise + Run 60 min")
        #expect(WorkoutFormat.strength(StrengthStep(exerciseKey: "Row", garminCategory: "ROW", sets: 3, reps: 12, weightKg: 50, restSeconds: 120)) == "3 × 12 · 50 kg · rest 2:00")
    }

    @Test func importBucketsSayNoneNotZero() {
        #expect(WorkoutFormat.bucket(ImportBucket(count: 0)) == "None")
        #expect(WorkoutFormat.bucket(ImportBucket(count: 2, names: ["A", "B"])) == "A, B")
        #expect(WorkoutFormat.garminLabel(.outdated) == "Garmin outdated")
    }
}


// W-B40 fixer: the editor and Import sheet are reachable by a scripted simulator run.
@Test func workoutLibraryLaunchRouteParsesItsArgument() {
    #expect(workoutLibraryLaunchRoute(["app", "-workout-library-open", "new"]) == .newWorkout)
    #expect(workoutLibraryLaunchRoute(["app", "-workout-library-open", "import"]) == .importSheet)
    #expect(workoutLibraryLaunchRoute(["app", "-workout-library-open", "t9"]) == .edit(9))
    #expect(workoutLibraryLaunchRoute(["app", "-workout-library-open", "x"]) == nil)
    #expect(workoutLibraryLaunchRoute(["app", "-workout-library-open"]) == nil)
    #expect(workoutLibraryLaunchRoute(["app"]) == nil)
}
