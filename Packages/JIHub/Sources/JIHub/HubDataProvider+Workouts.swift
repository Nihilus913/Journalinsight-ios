import JICore

/// W-B40 L2 (B-40b-2) — `WorkoutLibraryProviding` over spec §3's routes under
/// `/api/v1/planning/workout-templates`, on the `send(method, path, body)` seam. The app queues
/// create / update / delete through the `Outbox` first (spec §10.4, `WorkoutLibraryOutbox`);
/// push-to-Garmin and import are hub-only and never queued. `HubClient.send` encodes with a plain
/// `JSONEncoder()`, so the draft goes out already snake-cased (`WorkoutTemplateDraft.wireBody()`,
/// the W-TGT pattern). 503 = `GarminAuthError` on the mini: surfaced as `HubError.http(503,
/// detail)` with the hub's own text.
///
/// X-1 (exit-plan change 1, the W-FIX8 targets-wipe shape): every template write goes through
/// here, so the guard lives here — a body with no segment, or only empty segments, is refused
/// before anything is sent (`WorkoutTemplateWouldClear`). A cold cache or an empty first-launch
/// editor can therefore never overwrite a hub template's prescription.
extension HubDataProvider: WorkoutLibraryProviding {
    // Literal paths (not interpolated from a constant) so `WritePathContractTests`'s inventory
    // sees every write and holds a review line for it.
    public func createWorkoutTemplate(_ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        try await client.send("POST", "/api/v1/planning/workout-templates", body: try Self.guardedBody(draft, templateId: nil))
    }

    public func updateWorkoutTemplate(id: Int, _ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        try await client.send("PUT", "/api/v1/planning/workout-templates/\(id)", body: try Self.guardedBody(draft, templateId: id))
    }

    public func deleteWorkoutTemplate(id: Int) async throws {
        try await client.delete("/api/v1/planning/workout-templates/\(id)")
    }

    public func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult {
        try await client.send("POST", "/api/v1/planning/workout-templates/\(id)/push-garmin", body: JSONValue?.none)
    }

    public func importWorkoutsFromGarmin() async throws -> GarminImportReport {
        try await client.send("POST", "/api/v1/planning/workout-templates/import-garmin", body: JSONValue?.none)
    }

    static func guardedBody(_ draft: WorkoutTemplateDraft, templateId: Int?) throws -> JSONValue {
        guard !draft.segments.isEmpty, draft.segments.allSatisfy({ !$0.steps.isEmpty }) else {
            throw WorkoutTemplateWouldClear(templateId: templateId)
        }
        do { return try draft.wireBody() } catch { throw HubError.decoding("/api/v1/planning/workout-templates: encode \(error)") }
    }
}
