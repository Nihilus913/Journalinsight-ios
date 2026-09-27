import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// B-57 W4 C4: the daytime-HRV row + medication check on KpiDetail (manual entry). Daytime HRV is
// context only; the hold is display state and changes no verdict.
@MainActor struct KpiDaytimeHrvTests {
    private func make(metric: KpiMetricId = .hrv, med: MedicationEntry?, daytime: Double? = 14) throws -> (KpiDetailViewModel, MedicationStore) {
        let db = try AppDatabase.inMemory()
        let store = MedicationStore(prefs: PrefStore(db: db))
        try store.save(med)
        let vm = KpiDetailViewModel(metric: metric, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
                                    targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: db),
                                    medicationStore: store, daytimeHrv: daytime)
        vm.loadMedication()
        return (vm, store)
    }

    private let concerta = MedicationEntry(name: "Concerta", dose: "36 mg", usualTime: ReminderTime(hour: 8, minute: 30), worksForHours: 12)

    @Test func unconfirmedMedicationPutsDaytimeHrvOnHold() throws {
        let (vm, _) = try make(med: concerta)
        #expect(vm.showsMedicationCard)
        #expect(vm.daytimeState.word == "On hold · confirm below")
        #expect(vm.medicationCardBody == "You added Concerta. Some medications raise heart rate and lower HRV while they work. Is it yours and current?")
        #expect(vm.daytimeValueText == "14 ms" && vm.daytimeReason == nil)
    }

    @Test func yesSetsAsideNoCountsAndBothPersist() throws {
        let (vm, store) = try make(med: concerta)
        vm.answerMedication(true)
        #expect(vm.daytimeState == .setAside(window: "08:30–20:30"))
        #expect(store.load()?.answer == .yes)
        vm.answerMedication(false)
        #expect(vm.daytimeState == .contextOnly)
        #expect(store.load()?.answer == .no)
        vm.resetMedicationAnswer()
        #expect(vm.daytimeState == .onHold)
        #expect(store.load()?.answer == .unconfirmed)
    }

    /// Review Focus 5: a name without a time/duration never shows a made-up window.
    @Test func noWindowSaysAddHowLongItWorks() throws {
        let (vm, _) = try make(med: MedicationEntry(name: "Concerta"))
        vm.answerMedication(true)
        #expect(vm.daytimeState.word == "Set aside · add how long it works")
    }

    @Test func noMedicationNoCardAndOtherMetricsNever() throws {
        #expect(try make(med: nil).0.showsMedicationCard == false)
        #expect(try make(med: nil).0.daytimeState == .contextOnly)
        #expect(try make(metric: .rhr, med: concerta).0.showsMedicationCard == false)
    }

    @Test func missingDaytimeValueIsNoDataNeverZero() throws {
        let (vm, _) = try make(med: nil, daytime: nil)
        #expect(vm.daytimeValueText == "—")
        #expect(vm.daytimeReason == "No data")
    }

    @Test func loadReadsTheStoredMedication() async throws {
        let db = try AppDatabase.inMemory()
        let store = MedicationStore(prefs: PrefStore(db: db))
        try store.save(concerta)
        let vm = KpiDetailViewModel(metric: .hrv, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
                                    targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: db), medicationStore: store)
        #expect(vm.medication == nil)
        await vm.load()
        #expect(vm.medication?.name == "Concerta")
    }
}
