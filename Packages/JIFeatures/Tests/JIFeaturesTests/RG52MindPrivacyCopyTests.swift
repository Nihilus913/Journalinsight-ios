import Testing
@testable import JIFeatures

/// RG-52 (B-24): the Mind privacy copy must stay true when the mood -> Apple Health mirror is on.
@Suite struct RG52MindPrivacyCopyTests {
    @Test func mirrorOffSaysOnThisPhoneOnly() {
        let c = mindPrivacyCopy(mirrorOn: false)
        #expect(c.subtitle == "On this phone only")
        #expect(c.footer.hasSuffix("Everything stays on your device."))
    }

    @Test func mirrorOnNamesAppleHealth() {
        let c = mindPrivacyCopy(mirrorOn: true)
        #expect(c.subtitle == "On this phone · mood also in Apple Health")
        #expect(!c.footer.contains("Everything stays on your device"))
        #expect(c.footer.contains("also written to Apple Health"))
        #expect(!c.subtitle.contains("only"))
    }
}
