import SwiftUI
import Testing
import JIDesign
@testable import JIFeatures

// B-33 §1: accents re-tint to system tints under `.native`; persisted rawValues never change.
@Test func accentRawValuesAreStable() {
    #expect(AccentKey.allCases.map(\.rawValue) == ["emerald", "teal", "indigo", "orange", "fuchsia"])
}

@Test func nativeAccentsAreSystemTints() {
    #expect(AccentKey.emerald.color(for: .native) == Color.green)
    #expect(AccentKey.teal.color(for: .native) == Color.teal)
    #expect(AccentKey.indigo.color(for: .native) == Color.indigo)
    #expect(AccentKey.orange.color(for: .native) == Color.orange)
    #expect(AccentKey.fuchsia.color(for: .native) == Color.pink)
}

@Test func classicAccentIsTheHex() {
    #expect(AccentKey.emerald.color(for: .classic) == AccentKey.emerald.color)
}
