import Testing
@testable import JICore

@Test func hubAllCoversEveryDomainButNotSDNN() {
    #expect(DataCapability.hubAll.contains(.gate))
    #expect(DataCapability.hubAll.contains(.bodyBattery))
    #expect(!DataCapability.hubAll.contains(.hrvSDNN))
}

@Test func gatedTileReadsBitmap() {
    let t2: DataCapability = [.recovery, .hrvSDNN]
    #expect(t2.contains(.recovery))
    #expect(!t2.contains(.bodyBattery))
}
