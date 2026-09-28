import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B40 L2 (B-40b-2) — `HubDataProvider+Workouts.swift` over spec §3's routes, plus the X-1
/// write-path contract (XC half): a segment-less body is never sent.
extension HubClientTests {
    private func workoutsProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    private func sentBody(_ request: URLRequest?) throws -> [String: Any] {
        var data = Data()
        if let stream = request?.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        } else {
            data = try #require(request?.httpBody)
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let route = "/api/v1/planning/workout-templates"

    private static let row = #"""
    {"template_id": 12, "name": "Easy Z2", "activity": "running", "location": "outdoor", "weekdays": [],
     "steps": [], "segments": [{"sport": "running", "steps": [{"purpose": "work", "end": {"type": "time", "seconds": 1800},
     "target": {"type": "hr_zone", "zone": 2}, "repeat": 1}]}], "description": null, "garmin": null,
     "updated_at": "2026-09-28T10:00:00Z"}
    """#

    private static let draft = WorkoutTemplateDraft(
        name: "Easy Z2", activity: "running", location: .outdoor, description: nil,
        segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 1800), target: .hrZone(2)))])])

    @Test func createPostsTheSnakeCaseDraftAndDecodesTheRow() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST \(Self.route)"] = (201, Data(Self.row.utf8))
        let created = try await workoutsProvider().createWorkoutTemplate(Self.draft)
        #expect(created.templateId == 12 && created.segments.count == 1)
        #expect(StubURLProtocol.log == ["POST \(Self.route)"])
        let body = try sentBody(StubURLProtocol.lastRequest)
        #expect(body["name"] as? String == "Easy Z2")
        let seg = try #require((body["segments"] as? [[String: Any]])?.first)
        let step = try #require((seg["steps"] as? [[String: Any]])?.first)
        #expect((step["target"] as? [String: Any])?["type"] as? String == "hr_zone")
        #expect(body.keys.contains("description"), "description is always sent (null clears it)")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func updatePutsToTheTemplateId() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["PUT \(Self.route)/12"] = (200, Data(Self.row.utf8))
        let updated = try await workoutsProvider().updateWorkoutTemplate(id: 12, Self.draft)
        #expect(updated.templateId == 12)
        #expect(StubURLProtocol.log == ["PUT \(Self.route)/12"])
    }

    @Test func deleteSendsDelete() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["DELETE \(Self.route)/12"] = (204, Data())
        try await workoutsProvider().deleteWorkoutTemplate(id: 12)
        #expect(StubURLProtocol.log == ["DELETE \(Self.route)/12"])
    }

    @Test func pushAndImportArePostsWithNoLocalLibraryInTheBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST \(Self.route)/12/push-garmin"] = (200, Data(#"{"garmin_workout_id": 1633309901}"#.utf8))
        StubURLProtocol.methodResponses["POST \(Self.route)/import-garmin"] = (200, Data(#"{"linked": ["Long Run Zone 2"], "created": 9, "skipped": []}"#.utf8))
        let provider = workoutsProvider()
        #expect(try await provider.pushWorkoutTemplateToGarmin(id: 12).garminWorkoutId == 1633309901)
        let report = try await provider.importWorkoutsFromGarmin()
        #expect(report.linked.names == ["Long Run Zone 2"] && report.created.count == 9 && report.skipped.count == 0)
        #expect(StubURLProtocol.log == ["POST \(Self.route)/12/push-garmin", "POST \(Self.route)/import-garmin"])
        #expect(StubURLProtocol.lastRequest?.httpBody == nil && StubURLProtocol.lastRequest?.httpBodyStream == nil,
                "import sends nothing from the phone — the hub reads Garmin itself")
    }

    @Test func garminSessionExpiredIs503WithTheHubsDetail() async {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST \(Self.route)/12/push-garmin"] = (503, Data(#"{"detail": "Garmin session expired — re-auth on the mini"}"#.utf8))
        await #expect(throws: HubError.http(status: 503, detail: "Garmin session expired — re-auth on the mini")) {
            _ = try await self.workoutsProvider().pushWorkoutTemplateToGarmin(id: 12)
        }
    }

    // MARK: X-1 (exit-plan change 1, XC half)

    /// An empty / first-launch editor body can never replace a hub template's prescription:
    /// refused BEFORE the network, for both write verbs.
    @Test func segmentlessWriteIsRefusedWithoutAnyRequest() async {
        StubURLProtocol.reset()
        let empty = WorkoutTemplateDraft(name: "Easy Z2", activity: "running", location: .outdoor, description: nil, segments: [])
        let provider = workoutsProvider()
        await #expect(throws: WorkoutTemplateWouldClear(templateId: 12)) { _ = try await provider.updateWorkoutTemplate(id: 12, empty) }
        await #expect(throws: WorkoutTemplateWouldClear(templateId: nil)) { _ = try await provider.createWorkoutTemplate(empty) }
        let stepless = WorkoutTemplateDraft(name: "X", activity: "running", location: .outdoor, description: nil,
                                            segments: [WorkoutSegment(sport: .running, steps: [])])
        await #expect(throws: WorkoutTemplateWouldClear(templateId: 12)) { _ = try await provider.updateWorkoutTemplate(id: 12, stepless) }
        #expect(StubURLProtocol.log.isEmpty, "nothing reached the hub")
    }
}
