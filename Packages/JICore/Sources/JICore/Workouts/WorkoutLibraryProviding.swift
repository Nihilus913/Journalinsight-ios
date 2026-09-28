import Foundation

/// W-B40 L2 (B-40b-2) — the library's write slice over spec §3's routes
/// (`/api/v1/planning/workout-templates`): create / update / delete (queued through the `Outbox`
/// by the app, spec §10.4) and the two hub-only Garmin actions (disabled offline, never queued).
/// The read is `WorkoutTemplatesProviding.workoutTemplates()` — one list for the library, the
/// B-37 Send-to-Watch sheet and B-82's picker (no second provider).
public protocol WorkoutLibraryProviding: WorkoutTemplatesProviding {
    /// `POST /api/v1/planning/workout-templates`
    func createWorkoutTemplate(_ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate
    /// `PUT /api/v1/planning/workout-templates/{id}`
    func updateWorkoutTemplate(id: Int, _ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate
    /// `DELETE /api/v1/planning/workout-templates/{id}`
    func deleteWorkoutTemplate(id: Int) async throws
    /// `POST /api/v1/planning/workout-templates/{id}/push-garmin` (hub-only; 503 = Garmin session expired)
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult
    /// `POST /api/v1/planning/workout-templates/import-garmin` (hub-only, idempotent)
    func importWorkoutsFromGarmin() async throws -> GarminImportReport
}

/// W-B40 X-1 (exit-plan change 1, the targets-wipe shape): a template write whose body carries NO
/// segments is refused on the phone before anything is sent — an empty first-launch / cold-cache
/// editor state can never replace a hub template's prescription. (The hub refuses it too: spec §3
/// "≥1 segment".)
public struct WorkoutTemplateWouldClear: Error, Equatable, Sendable {
    public let templateId: Int?
    public init(templateId: Int?) { self.templateId = templateId }
}

/// The editable body of a template write (spec §3 POST / PUT). Weekdays are NOT part of it —
/// they stay B-45's plan-session assignment (spec §10.3); the hub owns `template_id`,
/// `updated_at`, `steps` (compat, derived) and `garmin`.
public struct WorkoutTemplateDraft: Codable, Sendable, Equatable {
    public var name: String
    public var activity: String
    public var location: WorkoutLocation
    public var description: String?
    public var segments: [WorkoutSegment]

    public init(name: String, activity: String, location: WorkoutLocation, description: String?, segments: [WorkoutSegment]) {
        self.name = name; self.activity = activity; self.location = location
        self.description = description; self.segments = segments
    }

    /// The editable fields of an existing row (a pre-053 row contributes its derived segment).
    public init(_ template: WorkoutTemplate) {
        self.init(name: template.name, activity: template.activity, location: template.location,
                  description: template.description, segments: template.effectiveSegments)
    }

    private enum CodingKeys: String, CodingKey { case name, activity, location, description, segments }

    /// `description` is always written (null when cleared) so a PUT really clears it.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(activity, forKey: .activity)
        try c.encode(location, forKey: .location)
        try c.encode(description, forKey: .description)
        try c.encode(segments, forKey: .segments)
    }

    /// The snake_case wire body for `HubClient.send` (plain `JSONEncoder()`), W-TGT pattern.
    public func wireBody() throws -> JSONValue { try JSONValue.snakeCased(self) }

    /// A template row showing this draft before the hub has answered (offline-first, B-52).
    public func previewTemplate(id: Int, basedOn existing: WorkoutTemplate? = nil, updatedAt: String) -> WorkoutTemplate {
        WorkoutTemplate(templateId: id, name: name, activity: activity, location: location,
                        weekdays: existing?.weekdays ?? [], steps: existing?.steps ?? [], updatedAt: updatedAt,
                        segments: segments, description: description,
                        garmin: existing?.garmin.map { GarminLink(workoutId: $0.workoutId, current: false, pushedAt: $0.pushedAt) })
    }
}

/// `POST /{id}/push-garmin` answer. Only the id is read; the library re-reads the list for the
/// hub's own version stamp (never computes *current* on the phone).
public struct GarminPushResult: Codable, Sendable, Equatable {
    public var garminWorkoutId: Int?
    public init(garminWorkoutId: Int?) { self.garminWorkoutId = garminWorkoutId }

    private enum CodingKeys: String, CodingKey { case garminWorkoutId, workoutId }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        garminWorkoutId = try c.decodeIfPresent(Int.self, forKey: .garminWorkoutId) ?? c.decodeIfPresent(Int.self, forKey: .workoutId)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(garminWorkoutId, forKey: .garminWorkoutId)
    }
}

/// `POST /import-garmin` answer — the ImportReport (spec §3): linked / created / skipped. Each
/// bucket is accepted as a count or as a list of names (or `{name, …}` objects), so the sheet
/// shows what the hub said without the phone guessing a shape.
public struct GarminImportReport: Codable, Sendable, Equatable {
    public var linked: ImportBucket
    public var created: ImportBucket
    public var skipped: ImportBucket

    public init(linked: ImportBucket, created: ImportBucket, skipped: ImportBucket) {
        self.linked = linked; self.created = created; self.skipped = skipped
    }

    private enum CodingKeys: String, CodingKey { case linked, created, skipped }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        linked = try c.decodeIfPresent(ImportBucket.self, forKey: .linked) ?? ImportBucket(count: 0)
        created = try c.decodeIfPresent(ImportBucket.self, forKey: .created) ?? ImportBucket(count: 0)
        skipped = try c.decodeIfPresent(ImportBucket.self, forKey: .skipped) ?? ImportBucket(count: 0)
    }
}

public struct ImportBucket: Codable, Sendable, Equatable {
    public var count: Int
    public var names: [String]

    public init(count: Int, names: [String] = []) { self.count = count; self.names = names }

    private struct Named: Decodable { let name: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self.init(count: n); return }
        if let names = try? c.decode([String].self) { self.init(count: names.count, names: names); return }
        let rows = try c.decode([Named].self)
        self.init(count: rows.count, names: rows.map(\.name))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        if names.isEmpty { try c.encode(count) } else { try c.encode(names) }
    }
}
