import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

// W-FIX7 L2 "Numbers + UI": F7-2, F7-3, F7-5, F7-6 (HealthTraining
// docs/audits/2026-09-25-regression-bugs.md, section "Device 2026-09-28"). The 2026-09-28 payload is
// the prod hub's `/planning/morning` (`fix6Morning20260928JSON`): gate_signals recovery = 36.

private func fix7Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

private func morning0928Signals() throws -> [GateSignal]? {
    try JSON.decoder.decode(MorningResponse.self, from: Data(fix6Morning20260928JSON.utf8)).gateSignals
}

private func onDevice(_ status: RecoveryScoreStatus, score: Int?, nights: Int = 14) -> RecoveryScoreResult {
    RecoveryScoreResult(status: status, score: score, raw: score.map(Double.init),
                        components: [RecoveryComponent(key: .hrv, status: .ok, value: 30, z: 0, normalN: 14)], nights: nights)
}

// MARK: - F7-2: Decide's "Recovery score" row = the ring's number (the hub's recovery)

@Test func f72RecoveryRowShowsTheHubsRecoveryOnThe0928Fixture() throws {
    let hub = decideHubRecovery(try morning0928Signals())
    #expect(hub == 36)
    // The phone computed 37 from recovery-inputs; the row must say what the ring says.
    let text = recoveryScoreCardText(result: onDevice(.ok, score: 37), reasonWord: nil, hubRecovery: hub)
    #expect(text.numeral == "36")
    #expect(text.numeral == jiNumber(decideRingScore(readiness: nil, recovery: onDevice(.ok, score: 37), hubRecovery: hub)!, 0))
    #expect(text.caption == "In your normal range")
    // Below the gate's floor the words say so.
    #expect(recoveryScoreCardText(result: nil, reasonWord: nil, hubRecovery: 20).caption == "Recovery low")
    // A calibrating phone never hides the hub's number.
    #expect(recoveryScoreCardText(result: onDevice(.calibrating, score: nil, nights: 3), reasonWord: nil, hubRecovery: hub).numeral == "36")
}

@Test func f72WithoutAHubRecoveryTheOnDeviceScoreStays() {
    #expect(recoveryScoreCardText(result: onDevice(.ok, score: 37), reasonWord: nil, hubRecovery: nil).numeral == "37")
    let none = recoveryScoreCardText(result: nil, reasonWord: nil, hubRecovery: nil)
    #expect(none.numeral == "—" && none.caption == "No data")
}

// MARK: - F7-3: Apple Health › Computed from these = the hub's values, or "—" + a reason

@Test func f73ReadinessTileIsTheHubsRecoveryOnThe0928Fixture() throws {
    let hubReadiness = try #require(healthHubReadiness(try morning0928Signals()))
    #expect(healthIsHubReadiness(hubReadiness))
    let tiles = healthComputedTiles(sleepScore: 94, readiness: hubReadiness)
    #expect(tiles[0].id == "readiness" && tiles[0].value == "36")
    #expect(tiles[0].note == "hub, today's call")
    #expect(tiles[1].id == "sleep" && tiles[1].value == "94" && tiles[1].note == "hub, Apple night")
}

@Test func f73MissingValuesSayWhy() throws {
    #expect(healthHubReadiness(nil) == nil)
    #expect(healthHubReadiness([]) == nil)
    let tiles = healthComputedTiles(sleepScore: nil, readiness: nil)
    for tile in tiles {
        if tile.value == "—" { #expect(!tile.note.isEmpty) }
    }
    // Sleep score without a hub value: the reason word, not the source.
    #expect(tiles[1].value == "—" && tiles[1].note == "No data")
    // The on-device score keeps its own source note and is not mistaken for the hub's.
    #expect(!healthIsHubReadiness(onDevice(.ok, score: 37)))
    #expect(healthComputedTiles(sleepScore: nil, readiness: onDevice(.ok, score: 37))[0].note == "JI, Apple signals")
}

// MARK: - F7-5: Trends › Body tiles equal height with the dated caption

@Test func f75BodyGroupReservesTheAsOfLineWhenAnyCardHasOne() {
    func c(_ id: String, asOf: String?) -> TrendsCardModel {
        TrendsCardModel(id: id, group: .body, name: id, systemImage: "circle", unit: nil, decimals: 0, value: 1,
                        tint: .muted, status: .contextOnly, asOf: asOf)
    }
    #expect(trendsReservesAsOfLine([c("weight", asOf: "as of 19 Sep"), c("steps", asOf: nil)]))
    #expect(!trendsReservesAsOfLine([c("weight", asOf: nil), c("steps", asOf: nil)]))
    // The reserved line keeps the dated caption's text on the card that has one.
    #expect(trendsAsOfLineText(c("weight", asOf: "as of 19 Sep"), reserve: true) == "as of 19 Sep")
    #expect(trendsAsOfLineText(c("steps", asOf: nil), reserve: true) == " ")
    #expect(trendsAsOfLineText(c("steps", asOf: nil), reserve: false) == nil)
}

// MARK: - F7-6: one primary button on Apple Health

@Test func f76BackloadIsNotASecondPrimary() throws {
    let backload = try fix7Source("Sources/JIFeatures/Settings/HealthBackloadSection.swift")
    #expect(!backload.contains(".jiPrimary"))
    #expect(backload.contains(".jiSecondary"))
    #expect(healthBackloadButtonRole == .secondary)
    // The board above keeps its one primary (Connect / Open Health settings).
    let board = try fix7Source("Sources/JIFeatures/Health/HealthPermissionView.swift")
    #expect(board.components(separatedBy: ".buttonStyle(.jiPrimary)").count - 1 == 1)
}
