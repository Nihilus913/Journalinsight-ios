import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F3 — report §4.1 page ground.

@Test func groundIsNotBlackAndCarriesTheTwoGlows() {
    var env = EnvironmentValues(); env.colorScheme = .dark
    let base = JIPageGround.darkBase.resolve(in: env)
    #expect(base.red > 0.03 && base.blue > base.red)   // #0B0D11: a blue-black, never #000
    #expect(JIPageGround.darkStops.count == 3)
    #expect(JIPageGround.accentGlowOpacity == 0.10)
    #expect(JIPageGround.sleepGlowOpacity == 0.07)
    #expect(JIPageGround.accentGlowOpacityLight == 0.06)
}

@MainActor
@Test func pageGroundRenders() {
    expectRenders("JIPageGround") { JIPageGround() }
    expectRenders("jiPageGround modifier") { Text("x").jiPageGround() }
}
