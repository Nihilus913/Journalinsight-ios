import Testing
@testable import JICore

@Test func packageLoads() {
    #expect(JICore.version == "0.1.0")
}
