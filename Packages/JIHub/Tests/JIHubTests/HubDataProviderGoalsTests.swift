import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `GoalsProviding` conformance (`HubDataProvider+Goals.swift`,
/// W4-L3). Same `StubURLProtocol`-backed construction as `HubDataProviderWeighInTests`, merged
/// into `HubClientTests`' `.serialized` suite convention.
extension HubClientTests {
    private func goalsProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    /// `StubURLProtocol.lastRequest?.httpBody` reads `nil` for a request built with `URLSession`
    /// (the body is delivered as `httpBodyStream` instead once it reaches the protocol) — read the
    /// stream directly rather than editing the shared `StubURLProtocol` fixture (owned outside
    /// this lane).
    private func drainBody(_ request: URLRequest?) throws -> Data {
        guard let stream = request?.httpBodyStream else { return try #require(request?.httpBody) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test func updateGoalsPutsWithBearerAndDecodesResult() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/goals"] = (200, Data("""
        {"weight":{"base_kg":80.2,"target_kg":74.0,"target_date":"2026-10-31"},
         "strength":[{"exercise":"bench","target_kg":102.5},{"exercise":"row","target_kg":100}],
         "steps_daily":15000,
         "nutrition":{"kcal_goal":1800,"protein_g":172,"carbs_g":160,"fat_g":52}}
        """.utf8))
        let provider = goalsProvider()
        let patch = GoalsUpdate(
            weight: .init(targetKg: 74.0, targetDate: "2026-10-31"),
            strength: [.init(exercise: "bench", targetKg: 102.5), .init(exercise: "row", targetKg: 100)],
            stepsDaily: 15000,
            nutrition: .init(kcalGoal: 1800, proteinG: 172, carbsG: 160, fatG: 52)
        )
        let result = try await provider.updateGoals(patch)
        #expect(result.weight.targetKg == 74.0)
        #expect(result.strength.first?.exercise == "bench")

        #expect(StubURLProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/goals")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")

        let body = try drainBody(StubURLProtocol.lastRequest)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == Set(["weight", "strength", "steps_daily", "nutrition"]))
        let weight = try #require(json["weight"] as? [String: Any])
        #expect(Set(weight.keys) == Set(["target_kg", "target_date"]))
        let nutrition = try #require(json["nutrition"] as? [String: Any])
        #expect(Set(nutrition.keys) == Set(["kcal_goal", "protein_g", "carbs_g", "fat_g"]))
        let strength = try #require(json["strength"] as? [[String: Any]])
        #expect(strength.first?["exercise"] as? String == "bench")
        #expect(strength.first?["target_kg"] as? Double == 102.5)
    }

    @Test func updateGoalsOmitsFieldsNotProvided() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/goals"] = (200, Data("""
        {"weight":{"base_kg":null,"target_kg":74.0,"target_date":null},"strength":[],"steps_daily":null,
         "nutrition":{"kcal_goal":null,"protein_g":null,"carbs_g":null,"fat_g":null}}
        """.utf8))
        let provider = goalsProvider()
        _ = try await provider.updateGoals(GoalsUpdate(stepsDaily: 12000))

        let body = try drainBody(StubURLProtocol.lastRequest)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == Set(["steps_daily"]))
        #expect(json["steps_daily"] as? Int == 12000)
    }

    @Test func updateGoalsPropagatesUnauthorizedOn401() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/goals"] = (401, Data("{\"detail\":\"bad token\"}".utf8))
        let provider = goalsProvider()
        await #expect(throws: HubError.self) {
            _ = try await provider.updateGoals(GoalsUpdate(stepsDaily: 1000))
        }
    }
}
