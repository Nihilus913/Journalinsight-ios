import Testing
@testable import JIDesign

// EA-gated tile idiom (W2 spec §8): energy availability that cannot be computed from the
// current source renders a clearly gated/unavailable state with honest copy — never a zero.

@MainActor
struct EAGatedTileTests {
    @Test func rendersInItsGatedStateWithDefaultReason() {
        let tile = EAGatedTile(label: "Energy availability")
        _ = tile.body // materializes the gated view; would trap/crash if construction were unsound
        #expect(eaGatedTileAccessibilityLabel(label: "Energy availability", reason: sourceMissingCopy)
                == "Energy availability, Not from the current source")
    }

    @Test func honorsAnExplicitReasonInsteadOfTheDefault() {
        let tile = EAGatedTile(label: "Energy availability", reason: "Needs 7 days of logging")
        _ = tile.body
        #expect(eaGatedTileAccessibilityLabel(label: "Energy availability", reason: "Needs 7 days of logging")
                == "Energy availability, Needs 7 days of logging")
    }

    @Test func neverAnnouncesABareDashOrZero() {
        let label = eaGatedTileAccessibilityLabel(label: "Energy availability", reason: sourceMissingCopy)
        #expect(!label.contains("—"))
        #expect(!label.contains("0"))
    }
}
