import Testing
@testable import JIDesign

// B-47 (spec §2 exception): the uppercase idiom is retired — a section header is the title,
// title-case, at `.cardTitle`. The transform stays as the seam; it no longer transforms.
@Test func sectionHeaderTitleIsTheTitleUnchanged() {
    #expect(sectionHeaderTitle("Drivers") == "Drivers")
    #expect(sectionHeaderTitle("Today") == "Today")
    #expect(sectionHeaderTitle("") == "")
}

@Test @MainActor func sectionHeaderRenders() {
    expectRenders("JISectionHeader") { JISectionHeader("Drivers") }
}
