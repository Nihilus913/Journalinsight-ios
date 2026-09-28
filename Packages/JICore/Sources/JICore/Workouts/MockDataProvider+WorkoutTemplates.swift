import Foundation

/// B-37-L1 — `MockDataProvider`'s `WorkoutTemplatesProviding` conformance: the 4 seed rows of
/// `plan.workout_template` (migration 046), served from the library's own hub-contract fixture copy
/// (`Fixtures/hub-contract/planning_workout_templates.json`), same `fixtureURL(named:)` pattern as
/// `MockDataProvider+Goals.swift`.
extension MockDataProvider: WorkoutTemplatesProviding {
    public func workoutTemplates() async throws -> [WorkoutTemplate] {
        guard let url = Self.fixtureURL(named: "planning_workout_templates")
        else { throw HubError.decoding("missing fixture planning_workout_templates") }
        return try JSON.decoder.decode([WorkoutTemplate].self, from: Data(contentsOf: url))
    }
}

/// W-B40 L2 — previews and fixture screens: writes echo the draft back (nothing is stored; the
/// mock is stateless), Garmin actions answer an empty report.
extension MockDataProvider: WorkoutLibraryProviding {
    public func createWorkoutTemplate(_ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        draft.previewTemplate(id: 1000, updatedAt: "2026-09-28T00:00:00Z")
    }
    public func updateWorkoutTemplate(id: Int, _ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        draft.previewTemplate(id: id, updatedAt: "2026-09-28T00:00:00Z")
    }
    public func deleteWorkoutTemplate(id: Int) async throws {}
    public func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult { GarminPushResult(garminWorkoutId: nil) }
    public func importWorkoutsFromGarmin() async throws -> GarminImportReport {
        GarminImportReport(linked: ImportBucket(count: 0), created: ImportBucket(count: 0), skipped: ImportBucket(count: 0))
    }
}
