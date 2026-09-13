import Testing
@testable import JICore

@Test func mockServesFixtures() async throws {
    let p = MockDataProvider()
    #expect(p.capabilities == .hubAll)
    let m = try await p.morning()
    #expect(m.carbWatchFloor > 0)
    let r = try await p.recovery(windowDays: 28)
    #expect(!r.isEmpty)
}
