import Testing
@testable import JIDesign

@Test func sectionHeaderTitleIsUppercased() {
    #expect(sectionHeaderTitle("Drivers") == "DRIVERS")
}

@Test @MainActor func sectionHeaderRenders() {
    expectRenders("JISectionHeader") { JISectionHeader("Drivers") }
}
