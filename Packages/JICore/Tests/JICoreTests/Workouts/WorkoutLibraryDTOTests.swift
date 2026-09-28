import Foundation
import Testing
@testable import JICore

/// W-B40 L2 (B-40b-1) — the extended `WorkoutTemplate` wire contract (spec §2.1 / §3 GET):
/// `segments`, `description`, `garmin`, decoded from a literal snake_case body.
private func workoutsFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources/workouts"))
    return try Data(contentsOf: url)
}

@Suite struct WorkoutLibraryDTOTests {
    @Test func decodesSegmentsDescriptionAndGarminFromSpecSample() throws {
        let rows = try JSON.decoder.decode([WorkoutTemplate].self, from: workoutsFixture("templates_spec_sample"))
        #expect(rows.count == 3)

        let norwegian = rows[0]
        #expect(norwegian.segments.count == 1)
        #expect(norwegian.segments[0].sport == .running)
        let work = try #require(norwegian.segments[0].steps[1].cardio)
        #expect(work.purpose == .work && work.repeat == 4)
        #expect(work.end == .time(seconds: 240))
        #expect(work.target == .hrRange(lo: 160, hi: 175))
        #expect(norwegian.garmin == GarminLink(workoutId: 1633309901, current: true, pushedAt: "2026-09-28T09:00:00Z"))
        #expect(norwegian.garminState == .current)
        #expect(norwegian.description == nil)

        let friday = rows[1]
        #expect(friday.segments.map(\.sport) == [.strength, .running])
        #expect(friday.description == "Strength then an easy run")
        let warm = try #require(friday.segments[0].steps[0].cardio)
        #expect(warm.target == .none && warm.description == "Rope jumping")
        let bench = try #require(friday.segments[0].steps[1].strength)
        #expect(bench.exerciseKey == "Barbell Bench Press")
        #expect(bench.garminCategory == "BENCH_PRESS" && bench.garminExercise == "BARBELL_BENCH_PRESS")
        #expect(bench.sets == 3 && bench.reps == 12 && bench.seconds == nil)
        #expect(bench.weightKg == 40 && bench.restSeconds == 120)
        let plank = try #require(friday.segments[0].steps[2].strength)
        #expect(plank.reps == nil && plank.seconds == 45 && plank.garminExercise == nil)
        #expect(friday.segments[1].steps[0].cardio?.target == .hrZone(2))
        #expect(friday.garminState == .outdated)
        #expect(friday.hasStrength && friday.hasCardio)

        let drill = rows[2]
        #expect(drill.segments[0].steps[0].cardio?.end == .lap)
        #expect(drill.segments[0].steps[1].cardio?.end == .distance(meters: 800))
        #expect(drill.garmin == nil && drill.garminState == .notPushed)
    }

    /// The B-37 hub (and the 4-row hub-contract fixture) sends no `segments`: the template still
    /// decodes, and its compat `steps` become one running segment (time end, hr_range target).
    @Test func legacyRowWithoutSegmentsDerivesOneRunningSegment() throws {
        let json = Data(#"""
        [{"template_id": 1, "name": "Zone 2 40 min", "activity": "running", "location": "outdoor", "weekdays": [0],
          "steps": [{"purpose": "work", "seconds": 2400, "hr_lo": 117, "hr_hi": 138, "repeat": 1}],
          "updated_at": "2026-09-21T00:00:00Z"}]
        """#.utf8)
        let row = try #require(try JSON.decoder.decode([WorkoutTemplate].self, from: json).first)
        #expect(row.segments.isEmpty)
        #expect(row.garmin == nil && row.description == nil)
        let effective = row.effectiveSegments
        #expect(effective.count == 1 && effective[0].sport == .running)
        #expect(effective[0].steps == [.cardio(CardioStep(purpose: .work, end: .time(seconds: 2400), target: .hrRange(lo: 117, hi: 138)))])
    }

    @Test func stepRoundTripsThroughSnakeCaseWire() throws {
        let segment = WorkoutSegment(sport: .strength, steps: [
            .cardio(CardioStep(purpose: .warmup, end: .lap, target: .none, description: "Rope")),
            .strength(StrengthStep(exerciseKey: "Plank", garminCategory: "PLANK", sets: 3, seconds: 45, restSeconds: 60)),
        ])
        let wire = try JSON.encoder.encode(segment)
        let text = String(decoding: wire, as: UTF8.self)
        #expect(text.contains(#""exercise_key":"Plank""#))
        #expect(text.contains(#""rest_seconds":60"#))
        #expect(text.contains(#""end":{"type":"lap"}"#))
        #expect(text.contains(#""target":{"type":"none"}"#))
        #expect(!text.contains("reps"), "absent optionals are omitted, never null-filled")
        #expect(try JSON.decoder.decode(WorkoutSegment.self, from: wire) == segment)
    }

    @Test func unknownEndOrTargetTypeFailsLoudly() {
        let json = Data(#"{"sport": "running", "steps": [{"purpose": "work", "end": {"type": "calories"}, "target": {"type": "none"}, "repeat": 1}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSON.decoder.decode(WorkoutSegment.self, from: json) }
    }

    @Test func draftWireBodyIsSnakeCasedAndCarriesNoTemplateId() throws {
        let draft = WorkoutTemplateDraft(name: "Easy", activity: "running", location: .outdoor, description: nil,
                                         segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 1800), target: .hrZone(2)))])])
        guard case .object(let body) = try draft.wireBody() else { Issue.record("draft body is an object"); return }
        // HT `WorkoutTemplateIn` (extra="forbid"): no `activity` (derived hub-side), PUT = full replace.
        #expect(Set(body.keys) == ["name", "location", "description", "segments", "weekdays", "gated_template_id"])
        #expect(body["description"] == .null, "a cleared description is sent as null so a PUT really clears it")
        #expect(body["weekdays"] == .array([]) && body["gated_template_id"] == .null)
        #expect(body["template_id"] == nil)
    }

    /// PUT is a full replace on the hub: a draft built from a row carries its weekdays and gated
    /// id, so editing the steps never clears the B-45 day or the B-49 gated variant.
    @Test func draftFromTemplateCarriesWeekdaysAndGatedIdSoAPutClearsNothing() throws {
        var rows = try JSON.decoder.decode([WorkoutTemplate].self, from: workoutsFixture("templates_spec_sample"))
        rows[1].gatedTemplateId = 3
        let draft = WorkoutTemplateDraft(rows[1])
        #expect(draft.name == "Friday" && draft.segments == rows[1].segments && draft.description == rows[1].description)
        guard case .object(let body) = try draft.wireBody() else { Issue.record("object"); return }
        #expect(body["weekdays"] == .array([.int(4)]) && body["gated_template_id"] == .int(3))
    }

    /// W-B40 exit: the DTO decodes HT's golden (`tests/fixtures/garmin_workouts/templates_golden.json`,
    /// lane L1, copied verbatim into Resources/workouts).
    @Test func decodesTheHTGolden() throws {
        let rows = try JSON.decoder.decode([WorkoutTemplate].self, from: workoutsFixture("templates_golden"))
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { !$0.segments.isEmpty }, "every golden row carries segments")
        let longRun = try #require(rows.first { $0.name == "Long Run Zone 2" })
        #expect(longRun.garmin?.workoutId == 1633309938 && longRun.garminState == .current)
        #expect(longRun.steps.count == 3 && longRun.segments[0].steps.count == 3, "compat steps kept beside segments")
        let friday = try #require(rows.first { $0.name == "Friday" })
        #expect(friday.segments.map(\.sport) == [.strength, .running])
        #expect(friday.hasStrength && friday.steps.isEmpty && friday.garminState == .outdated)
        #expect(friday.segments[0].steps.contains { $0.strength != nil })
        #expect(rows.first { $0.name == "Norwegian 4×4" }?.gatedTemplateId == 2, "gated variant decodes (spec §10.2)")
        // Round trip through the write body decodes back to the same segments.
        for row in rows {
            let wire = try JSONEncoder().encode(WorkoutTemplateDraft(row).wireBody())
            #expect(try JSON.decoder.decode(WorkoutTemplateDraft.self, from: wire).segments == row.segments)
        }
    }

    @Test func legacyDraftFromSegmentlessTemplateUsesEffectiveSegments() {
        let t = WorkoutTemplate(templateId: 1, name: "Z2", activity: "running", location: .outdoor, weekdays: [],
                                steps: [WorkoutStep(purpose: .work, seconds: 60, hrLo: 110, hrHi: 130)], updatedAt: "x")
        #expect(WorkoutTemplateDraft(t).segments.count == 1, "never a zero-segment draft from a template that has steps")
    }

    @Test func importReportDecodesCountsOrNameLists() throws {
        let lists = try JSON.decoder.decode(GarminImportReport.self, from: Data(#"{"linked": ["Long Run Zone 2"], "created": ["Friday", "Drill"], "skipped": [{"name": "Zone 2", "reason": "edited in JI since import"}]}"#.utf8))
        #expect(lists.linked.count == 1 && lists.created.count == 2 && lists.skipped.count == 1)
        #expect(lists.skipped.names == ["Zone 2"])
        let ht = try JSON.decoder.decode(GarminImportReport.self, from: Data(#"{"created": ["A"], "linked": [], "updated": ["B"], "unchanged": ["C", "D"], "skipped": [{"name": "E", "reason": "edited"}], "coach_rows": 10}"#.utf8))
        #expect(ht.created.names == ["A"] && ht.updated.names == ["B"] && ht.unchanged.count == 2 && ht.skipped.names == ["E"])
        let counts = try JSON.decoder.decode(GarminImportReport.self, from: Data(#"{"linked": 1, "created": 9, "skipped": 0}"#.utf8))
        #expect(counts.linked.count == 1 && counts.created.count == 9 && counts.skipped.count == 0)
        #expect(counts.created.names.isEmpty)
    }
}
