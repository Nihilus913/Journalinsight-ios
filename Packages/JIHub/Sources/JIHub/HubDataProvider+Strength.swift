import Foundation
import JICore

/// W-B38-A A-8 — `HubDataProvider`'s strength-log routes (HT `app/planning/strength_log.py`,
/// card rows A-2..A-4). Writes are keyed on client UUIDs hub-side (same client_id twice → one row),
/// so the `strength` outbox can replay any of them. X-1: a `complete` whose advance list carries a
/// missing / non-positive weight is refused BEFORE sending (`StrengthAdvanceWouldClear`); an empty
/// advance list is legal (toggle off) and moves no target.
extension HubDataProvider {

    public func createStrengthSession(_ body: StrengthSessionCreate) async throws -> StrengthSessionOut {
        try await client.send("POST", "/api/v1/planning/strength-sessions", body: body)
    }

    public func logStrengthSet(session: String, _ body: StrengthSetIn) async throws -> StrengthWriteAck {
        try await client.send("POST", "/api/v1/planning/strength-sessions/\(session)/sets", body: body)
    }

    public func updateStrengthSet(session: String, clientId: String, _ body: StrengthSetIn) async throws -> StrengthWriteAck {
        try await client.send("PUT", "/api/v1/planning/strength-sessions/\(session)/sets/\(clientId)", body: body)
    }

    public func deleteStrengthSet(session: String, clientId: String) async throws {
        try await client.delete("/api/v1/planning/strength-sessions/\(session)/sets/\(clientId)")
    }

    public func completeStrengthSession(session: String, _ body: StrengthSessionComplete) async throws -> StrengthSessionOut {
        if let bad = body.advance.first(where: { !($0.currentWeightKg.isFinite && $0.currentWeightKg > 0) }) {
            throw StrengthAdvanceWouldClear(exerciseId: bad.exerciseId)
        }
        return try await client.send("POST", "/api/v1/planning/strength-sessions/\(session)/complete", body: body)
    }

    public func strengthSessions(from: String, to: String) async throws -> [StrengthSessionOut] {
        let list: StrengthSessionList = try await client.get("/api/v1/planning/strength-sessions", query: ["from": from, "to": to])
        return list.sessions
    }

    public func strengthLastSets(exerciseKey: String) async throws -> [StrengthSetOut] {
        let list: StrengthSetList = try await client.get("/api/v1/planning/strength-sessions/last-sets", query: ["exercise_key": exerciseKey])
        return list.sets
    }
}
