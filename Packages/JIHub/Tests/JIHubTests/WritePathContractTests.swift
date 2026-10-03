import Foundation
import Testing
import JICore
@testable import JIHub

/// W-FIX8 X-1 (exit plan change 2) — every app→hub WRITE in JIHub is reviewed for one property:
/// an empty / first-launch payload can never overwrite non-empty server state. The 2026-09-28
/// 14:51 P0 was exactly that (a first-launch EMPTY targets document PUT over Toby's goals).
///
/// Two halves: an inventory test that fails on any write call it has not seen (so a new write path
/// cannot land without a review line), and behaviour tests for the one full-replace document
/// (`PUT /planning/targets`). The other writes are append-only rows or keyed single-item edits:
/// their body cannot express "clear everything". Retired routes answer 405 on the hub
/// (HT tests/test_api_targets.py::test_old_write_routes_are_gone).
extension HubClientTests {
    private func writeProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    private static let targetsPath = "/api/v1/planning/targets"

    /// What the hub answers today (Toby's goals present).
    private static let hubWithGoals = """
    {"version":1,"updated_at":"2026-09-28T05:00:00+00:00",
     "goals":{"weight":{"base_kg":80.2,"target_kg":75.0,"target_date":"2026-10-31"},
              "kcal":{"goal_kcal":1935,"basis":"includes_deficit","deficit_kcal_per_day":null,"weekly_loss_kg":null,"target_kcal":1935},
              "protein_g":184.9,"carbs_g":172,"fat_g":59.125,"steps_daily":15000,"sleep_h":null,
              "strength":[{"exercise":"bench","target_kg":100.0}]},
     "limits":{"hr_cap_bpm":175,"hr_cap_confirmed_on":null,"zones":null,"avoid_zone5":true},
     "rules":{"hrv_low_nights":2,"resp_delta_amber":2,"carb_three_day_floor":120,"interval_min_sleep":6,
              "load_over":1.3,"load_under":0.8,"load_band_low":0.8,"load_band_high":1.3,
              "week_kcal_floor":1600,"week_protein_floor":130,"week_sleep_score_floor":55}}
    """
    private static let hubEmpty = """
    {"version":1,"goals":{"weight":null,"kcal":null,"protein_g":null,"carbs_g":null,"fat_g":null,
     "steps_daily":null,"sleep_h":null,"strength":[]},
     "limits":{"hr_cap_bpm":null,"hr_cap_confirmed_on":null,"zones":null,"avoid_zone5":false},
     "rules":{"hrv_low_nights":2}}
    """

    private func requestBody(_ request: URLRequest?) throws -> [String: Any] {
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

    // MARK: PUT /planning/targets — the full-replace document

    @Test func firstLaunchEmptyDocumentNeverPutsOverHubGoals() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["GET \(Self.targetsPath)"] = (200, Data(Self.hubWithGoals.utf8))
        StubURLProtocol.methodResponses["PUT \(Self.targetsPath)"] = (200, Data(Self.hubEmpty.utf8))
        var firstLaunch = TargetsDocument.empty
        firstLaunch.limits.hrCapBpm = 175          // onboarding wrote a cap; goals still empty
        do {
            _ = try await writeProvider().putTargets(firstLaunch)
            Issue.record("a goals-empty body was sent over hub goals")
        } catch let refused as TargetsWouldClearGoals {
            #expect(refused.server.goal(.protein) == 184.9)
            #expect(refused.server.goals.strength.count == 1)
        }
        #expect(StubURLProtocol.log == ["GET \(Self.targetsPath)"])   // zero PUT
    }

    @Test func emptyDocumentOverAnEmptyHubIsSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.targetsPath] = (200, Data(Self.hubEmpty.utf8))
        _ = try await writeProvider().putTargets(.empty)
        #expect(StubURLProtocol.log == ["GET \(Self.targetsPath)", "PUT \(Self.targetsPath)"])
        #expect(try requestBody(StubURLProtocol.lastRequest)["clear_all_goals"] == nil)
    }

    @Test func aDeliberateClearIsSentWithTheFlagAndNoPreflight() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.targetsPath] = (200, Data(Self.hubEmpty.utf8))
        var clear = TargetsDocument.empty
        clear.clearAllGoals = true
        _ = try await writeProvider().putTargets(clear)
        #expect(StubURLProtocol.log == ["PUT \(Self.targetsPath)"])
        #expect(try requestBody(StubURLProtocol.lastRequest)["clear_all_goals"] as? Bool == true)
    }

    @Test func aDocumentWithGoalsIsSentWithoutPreflight() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.targetsPath] = (200, Data(Self.hubWithGoals.utf8))
        var d = TargetsDocument.empty
        d.goals.stepsDaily = 12000
        _ = try await writeProvider().putTargets(d)
        #expect(StubURLProtocol.log == ["PUT \(Self.targetsPath)"])
    }

    @Test func theHubs409BecomesTheSameRefusal() async throws {
        // A hub whose goals appeared between the preflight and the PUT answers 409 (HT guard).
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["GET \(Self.targetsPath)"] = (200, Data(Self.hubWithGoals.utf8))
        StubURLProtocol.methodResponses["PUT \(Self.targetsPath)"] =
            (409, Data(#"{"detail":"This body has no goals and would clear every stored goal."}"#.utf8))
        var d = TargetsDocument.empty
        d.goals.sleepH = 7                          // not goals-empty: no preflight, the hub decides
        await #expect(throws: TargetsWouldClearGoals.self) { _ = try await self.writeProvider().putTargets(d) }
        #expect(StubURLProtocol.log == ["PUT \(Self.targetsPath)", "GET \(Self.targetsPath)"])
    }

    // MARK: The inventory — every write call in JIHub, reviewed

    /// "file: write" → why an empty / first-launch payload cannot wipe server state.
    private static let reviewedWrites: [String: String] = [
        "HubDataProvider+Targets.swift: PUT /api/v1/planning/targets":
            "full replace — goals-empty guard above (preflight GET + hub 409)",
        "HubDataProvider+Training.swift: PUT /api/v1/planning/exercises/\\(exerciseId)":
            "keyed patch of one exercise",
        "HubDataProvider+Training.swift: PUT /api/v1/planning/plan-sessions/\\(sessionId)":
            "keyed weekday of one session (required weekday)",
        "HubDataProvider+WeighIn.swift: POST /api/v1/vitals/weighin": "append one weigh-in (required weight)",
        "HubDataProvider+GateRespond.swift: POST /api/v1/planning/gate/respond": "append one gate response",
        "HubDataProvider+GateRespond.swift: POST /api/v1/planning/feel": "append one session feel",
        "HubDataProvider+VerdictOverride.swift: POST /api/v1/planning/verdict-override": "one day's override (required date)",
        "HubDataProvider+VerdictOverride.swift: DELETE /api/v1/planning/verdict-override": "one day's override (required date)",
        "HubDataProvider+Push.swift: POST /api/v1/planning/push-token": "upsert this device's token",
        // W-B40 X-1 (XC half): the workout library's writes — see HubDataProviderWorkoutsTests.
        "HubDataProvider+Workouts.swift: POST /api/v1/planning/workout-templates":
            "create one template; a segment-less draft is refused before sending (WorkoutTemplateWouldClear)",
        "HubDataProvider+Workouts.swift: PUT /api/v1/planning/workout-templates/\\(id)":
            "keyed replace of one template; a segment-less draft is refused before sending (hub: ≥1 segment)",
        "HubDataProvider+Workouts.swift: DELETE /api/v1/planning/workout-templates/\\(id)":
            "one keyed template, only from an explicit user delete",
        "HubDataProvider+Workouts.swift: POST /api/v1/planning/workout-templates/\\(id)/push-garmin":
            "no body; hub pushes its own stored row to Garmin",
        "HubDataProvider+Workouts.swift: POST /api/v1/planning/workout-templates/import-garmin":
            "no body; hub-side idempotent import, skips templates edited since import",
        // W-B38-A A-8: the strength log — append-only rows keyed by client UUID (replay = one row).
        "HubDataProvider+Strength.swift: POST /api/v1/planning/strength-sessions":
            "create one logged session (client_id unique hub-side)",
        "HubDataProvider+Strength.swift: POST /api/v1/planning/strength-sessions/\\(sessionLogId)/sets":
            "append one set (client_id unique hub-side)",
        "HubDataProvider+Strength.swift: PUT /api/v1/planning/strength-sessions/\\(sessionLogId)/sets/\\(clientId)":
            "keyed edit of one set",
        "HubDataProvider+Strength.swift: DELETE /api/v1/planning/strength-sessions/\\(sessionLogId)/sets/\\(clientId)":
            "one keyed set, only from an explicit user delete",
        "HubDataProvider+Strength.swift: POST /api/v1/planning/strength-sessions/\\(sessionLogId)/complete":
            "explicit advance list only; a null / <=0 kg move is refused before sending (StrengthAdvanceWouldClear), [] moves nothing",
    ]

    @Test func everyHubWriteIsReviewed() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JIHub")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.contains("HubDataProvider+Targets.swift"))
        let pattern = try NSRegularExpression(
            pattern: #"client\.(?:send\("([A-Z]+)",\s*"([^"]+)"|(post)\("([^"]+)"|(delete)\("([^"]+)")"#)
        var found: Set<String> = []
        for file in files where file != "HubClient.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let ns = text as NSString
            for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
                let method = group(1) ?? group(3).map { _ in "POST" } ?? "DELETE"
                let path = group(2) ?? group(4) ?? group(6) ?? "?"
                found.insert("\(file): \(method) \(path)")
            }
        }
        let unreviewed = found.subtracting(Self.reviewedWrites.keys)
        #expect(unreviewed.isEmpty, "unreviewed hub write(s): \(unreviewed.sorted())")
        #expect(found.count >= 10)   // the scan still sees the writes (guards against a regex that matches nothing)
    }

    /// W-FIX10 F10-1 (audit 03-F1): the three routes W-TGT removed hub-side are never written
    /// (`PUT /planning/goals` answered every GoalsSetup save with a 405, replayed forever).
    @Test func theRetiredRoutesAreNeverWritten() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JIHub")
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for retired in ["\"/api/v1/planning/goals\"", "\"/api/v1/planning/gate-settings\"", "/api/v1/planning/kpi-targets/"] {
                for line in text.split(separator: "\n") where line.contains(retired) {
                    #expect(!line.contains("send(\"PUT\""), "\(file) still writes \(retired)")
                }
            }
        }
    }

    @Test func anEmptyGoalsPatchClearsNothing() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GoalsUpdate())) as? [String: Any]
        #expect(body?.isEmpty == true)
    }
}
