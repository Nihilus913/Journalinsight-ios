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

/// The body of a template write (spec §3 POST / PUT; HT `WorkoutTemplateIn`). PUT is a FULL
/// replace on the hub, so every write carries the row's `weekdays` and `gated_template_id` as the
/// phone last saw them — a draft built from a template keeps them, so an edit of the steps never
/// clears the day assignment (B-45) or the gated variant (B-49). `activity` is NOT sent: the hub
/// derives it from the segments; it is kept here only for the phone-side preview row.
public struct WorkoutTemplateDraft: Codable, Sendable, Equatable {
    public var name: String
    public var activity: String
    public var location: WorkoutLocation
    public var description: String?
    public var segments: [WorkoutSegment]
    public var weekdays: [Int]
    public var gatedTemplateId: Int?

    public init(name: String, activity: String, location: WorkoutLocation, description: String?, segments: [WorkoutSegment],
                weekdays: [Int] = [], gatedTemplateId: Int? = nil) {
        self.name = name; self.activity = activity; self.location = location
        self.description = description; self.segments = segments
        self.weekdays = weekdays; self.gatedTemplateId = gatedTemplateId
    }

    /// The fields of an existing row (a pre-053 row contributes its derived segment).
    public init(_ template: WorkoutTemplate) {
        self.init(name: template.name, activity: template.activity, location: template.location,
                  description: template.description, segments: template.effectiveSegments,
                  weekdays: template.weekdays, gatedTemplateId: template.gatedTemplateId)
    }

    private enum WireKeys: String, CodingKey { case name, location, description, segments, weekdays, gatedTemplateId }
    private enum StoreKeys: String, CodingKey { case name, activity, location, description, segments, weekdays, gatedTemplateId }

    /// Wire shape: `description` / `gated_template_id` always written (null clears them on a PUT);
    /// no `activity` (HT's model forbids extra keys).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(location, forKey: .location)
        try c.encode(description, forKey: .description)
        try c.encode(segments, forKey: .segments)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(gatedTemplateId, forKey: .gatedTemplateId)
        // The outbox stores drafts with this same encoder, so a queued draft decodes with no
        // `activity` (→ "running"); the preview row takes its sport from the segments anyway.
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: StoreKeys.self)
        name = try c.decode(String.self, forKey: .name)
        activity = try c.decodeIfPresent(String.self, forKey: .activity) ?? "running"
        location = try c.decode(WorkoutLocation.self, forKey: .location)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        segments = try c.decode([WorkoutSegment].self, forKey: .segments)
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        gatedTemplateId = try c.decodeIfPresent(Int.self, forKey: .gatedTemplateId)
    }

    /// The snake_case wire body for `HubClient.send` (plain `JSONEncoder()`), W-TGT pattern.
    public func wireBody() throws -> JSONValue { try JSONValue.snakeCased(self) }

    /// A template row showing this draft before the hub has answered (offline-first, B-52).
    public func previewTemplate(id: Int, basedOn existing: WorkoutTemplate? = nil, updatedAt: String) -> WorkoutTemplate {
        let sport = segments.first(where: { $0.sport.isCardio })?.sport.rawValue
        return WorkoutTemplate(templateId: id, name: name, activity: sport ?? existing?.activity ?? activity, location: location,
                               weekdays: weekdays, steps: existing?.steps ?? [], updatedAt: updatedAt,
                               segments: segments, description: description,
                               garmin: existing?.garmin.map { GarminLink(workoutId: $0.workoutId, current: false, pushedAt: $0.pushedAt) },
                               gatedTemplateId: gatedTemplateId)
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
    /// HT `ImportReportOut` also reports re-imported rows (updated) and no-ops (unchanged).
    public var updated: ImportBucket
    public var unchanged: ImportBucket

    public init(linked: ImportBucket, created: ImportBucket, skipped: ImportBucket,
                updated: ImportBucket = ImportBucket(count: 0), unchanged: ImportBucket = ImportBucket(count: 0)) {
        self.linked = linked; self.created = created; self.skipped = skipped
        self.updated = updated; self.unchanged = unchanged
    }

    private enum CodingKeys: String, CodingKey { case linked, created, skipped, updated, unchanged }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        linked = try c.decodeIfPresent(ImportBucket.self, forKey: .linked) ?? ImportBucket(count: 0)
        created = try c.decodeIfPresent(ImportBucket.self, forKey: .created) ?? ImportBucket(count: 0)
        skipped = try c.decodeIfPresent(ImportBucket.self, forKey: .skipped) ?? ImportBucket(count: 0)
        updated = try c.decodeIfPresent(ImportBucket.self, forKey: .updated) ?? ImportBucket(count: 0)
        unchanged = try c.decodeIfPresent(ImportBucket.self, forKey: .unchanged) ?? ImportBucket(count: 0)
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
