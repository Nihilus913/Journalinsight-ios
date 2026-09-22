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

/// Phase C: one language left, so `color(for:)` is the system tint for every theme value.
/// `hex` survives only as the persisted prefs value and must not drift.
@Test func accentHexStaysThePersistedValue() {
    for theme in JITheme.allCases {
        #expect(AccentKey.emerald.color(for: theme) == AccentKey.emerald.nativeColor)
    }
    #expect(AccentKey.emerald.hex == 0x4ade80)
}
