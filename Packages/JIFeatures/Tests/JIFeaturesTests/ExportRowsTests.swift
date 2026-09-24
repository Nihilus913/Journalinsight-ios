import Testing
@testable import JIFeatures

struct ExportRowsTests {
    @Test func mindMergesCheckinsAndEvents() {
        #expect(ExportRow.allCases.map(\.label) == ["Journal entries", "Mind", "WHO-5", "Goals"])
        #expect(ExportRow.mind.types == [.checkins, .events])
    }

    @Test func aMindRowIsOnOnlyWhenBothAreOn() {
        #expect(exportRowSelected(.mind, isSelected: { $0 == .checkins }) == false)
        #expect(exportRowSelected(.mind, isSelected: { _ in true }))
    }

    @Test func togglingTheMindRowFlipsBothTogether() {
        // half-on → turn the missing one on
        #expect(exportRowToggles(.mind, isSelected: { $0 == .checkins }) == [.events])
        // all on → turn both off
        #expect(exportRowToggles(.mind, isSelected: { _ in true }) == [.checkins, .events])
    }

    @Test func headerNoLongerClaimsPhoneOnlyData() {
        #expect(exportHeaderCopy == "A readable copy of what you pick, as CSV or JSON. To move to a new phone, use Backup.")
        #expect(!exportHeaderCopy.contains("only lives on this phone"))
    }
}
