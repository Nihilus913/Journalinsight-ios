import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W5b-L3 → W-TGT L3: `GateConfigViewModel` is the Limits engine behind Settings › Targets (cap,
// re-check, zones, Avoid Zone 5, caution preset). The local morning-gate / KPI-rule overrides, the
// fixture preview and the live `plan.kpi_target` block ("Advanced") are deleted (spec §4) — their
// tests went with them; the Rules are tested on the targets document (`TargetsScreenTests`).

@MainActor
private func makeModel() throws -> (GateConfigViewModel, PrefStore) {
    let store = PrefStore(db: try AppDatabase.inMemory())
    return (GateConfigViewModel(prefStore: store), store)
}

@Test @MainActor func loadReadsTheStoredSettingsAndNothingElse() async throws {
    let (vm, store) = try makeModel()
    #expect(!vm.loaded)
    await vm.load()
    #expect(vm.loaded)
    #expect(vm.gateSettings == GateSettings())   // fresh install: no cap, no zones (never a default)
    try GateSettingsStore(prefs: store).save(GateSettings(preset: .push, hrCapBpm: 171))
    vm.loadLocal()
    #expect(vm.gateSettings.hrCapBpm == 171 && vm.gateSettings.preset == .push)
}

@Test @MainActor func afterTheImportTheEngineWritesTheTargetsDocument() async throws {
    let (vm, store) = try makeModel()
    try TargetsStore(prefs: store).save(.empty)
    await vm.load()
    _ = await vm.changeHrCap("169")
    #expect(await vm.setZones(anchor: .lthr, bpmText: "172"))
    await vm.setAvoidZone5(true)
    let doc = TargetsStore(prefs: store).load()
    #expect(doc.limits.hrCapBpm == 169)
    #expect(doc.limits.zones?.anchor == .lthr)
    #expect(doc.limits.avoidZone5)
    // The legacy key is not written once the document exists (one number per metric).
    let legacy: GateSettings?? = try? store.get(GateSettingsStore.key, as: GateSettings.self)
    #expect((legacy ?? nil) == nil)
}

@Test @MainActor func theSweepFixtureBuilds() {
    #expect(GateConfigViewModel.fixture()?.loaded == true)
}
