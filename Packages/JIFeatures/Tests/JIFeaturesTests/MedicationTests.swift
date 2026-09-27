import Testing
import JIDesign
import JIPersistence
@testable import JIFeatures

struct MedicationTests {
    private let named = MedicationEntry(name: "Concerta", dose: "36 mg", usualTime: ReminderTime(hour: 8, minute: 30), worksForHours: 12)

    @Test func nothingIsFilledInForYou() {
        let e = MedicationEntry()
        #expect(e.name.isEmpty && e.dose.isEmpty && e.usualTime == nil && e.worksForHours == nil)
        #expect(e.answer == .unconfirmed && e.source == .manual && e.frequency == .daily)
        #expect(!e.isNamed)
        #expect(!MedicationEntry(name: "   ").isNamed)
    }

    @Test func windowIsUsualTimePlusDurationAndWrapsMidnight() {
        #expect(named.windowText == "08:30–20:30")
        var late = named; late.usualTime = ReminderTime(hour: 20, minute: 0); late.worksForHours = 6
        #expect(late.windowText == "20:00–02:00")
        var noHours = named; noHours.worksForHours = nil
        #expect(noHours.windowText == nil)
        var noTime = named; noTime.usualTime = nil
        #expect(noTime.windowText == nil)
    }

    /// Review Focus 5.
    @Test func daytimeHrvStateWords() {
        #expect(daytimeHrvState(nil) == .contextOnly)
        #expect(daytimeHrvState(MedicationEntry()) == .contextOnly)                 // unnamed = nothing to confirm
        #expect(daytimeHrvState(named) == .onHold)
        #expect(DaytimeHrvState.onHold.word == "On hold · confirm below")
        #expect(DaytimeHrvState.onHold.role == .reduced)
        var yes = named; yes.answer = .yes
        #expect(daytimeHrvState(yes) == .setAside(window: "08:30–20:30"))
        #expect(DaytimeHrvState.setAside(window: "08:30–20:30").word == "Set aside 08:30–20:30")
        var yesNoHours = yes; yesNoHours.worksForHours = nil
        #expect(daytimeHrvState(yesNoHours).word == "Set aside · add how long it works")
        var no = named; no.answer = .no
        #expect(daytimeHrvState(no) == .contextOnly)
        var stopped = yes; stopped.frequency = .notAnymore
        #expect(daytimeHrvState(stopped) == .contextOnly)
        #expect(DaytimeHrvState.contextOnly.word == "Context only")
        #expect(DaytimeHrvState.contextOnly.role == .muted)
    }

    @Test @MainActor func storeRoundTripsAndClears() throws {
        let store = MedicationStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
        #expect(store.load() == nil)
        try store.save(named)
        #expect(store.load() == named)
        try store.save(nil)
        #expect(store.load() == nil)
    }
}
