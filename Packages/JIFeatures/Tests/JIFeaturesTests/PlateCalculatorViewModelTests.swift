import Foundation
import Testing
import JICompute
import JIPersistence
@testable import JIFeatures

/// W-B38-B B-9 — the plate calculator sheet from the phone set row (`PlateMath` per side) and the
/// user's plate inventory (Settings › Plates & bar; first launch = standard plates + microplates).
@MainActor
struct PlateCalculatorViewModelTests {
    private func store() throws -> PrefStore { PrefStore(db: try AppDatabase.inMemory()) }

    @Test func reachableLoadListsPlatesPerSideHeaviestFirst() {
        let vm = PlateCalculatorViewModel(totalKg: 52.5, inventory: PlateInventory(barKg: 20, pairs: [10, 5, 2.5, 1.25]))
        #expect(vm.outcome == .plates([10, 5, 1.25]))
        #expect(vm.perSideText == "10 + 5 + 1.25 kg each side")
        #expect(vm.headline == "52.5 kg on a 20 kg bar")
    }

    @Test func unreachableLoadSaysNotLoadableAndNeverGuesses() {
        let vm = PlateCalculatorViewModel(totalKg: 53, inventory: PlateInventory(barKg: 20, pairs: [10, 5, 2.5, 1.25]))
        #expect(vm.outcome == .notLoadable)
        #expect(vm.perSideText == "53 kg is not loadable with your plates")
    }

    @Test func emptyBarAndLighterThanTheBar() {
        #expect(PlateCalculatorViewModel(totalKg: 20, inventory: .default).outcome == .barOnly)
        #expect(PlateCalculatorViewModel(totalKg: 20, inventory: .default).perSideText == "Just the bar")
        #expect(PlateCalculatorViewModel(totalKg: 15, inventory: .default).outcome == .notLoadable)
    }

    @Test func noInventoryMeansNoCalculator() {
        let vm = PlateCalculatorViewModel(totalKg: 60, inventory: PlateInventory(barKg: 20, pairs: []))
        #expect(vm.outcome == .noInventory)
        #expect(!PlateInventory(barKg: 20, pairs: []).canCalculate)
        #expect(vm.perSideText == "Add your plates in Settings › Plates & bar")
    }

    @Test func inventoryDefaultsToStandardAndPersistsEdits() throws {
        let prefs = try store()
        #expect(PlateInventoryStore.load(from: prefs) == .default)
        #expect(PlateInventoryStore.key == PlateInventory.prefKey)   // one inventory with the A-10 logger
        #expect(PlateInventory.default.barKg == PlateMath.defaultBarKg)
        #expect(PlateInventory.default.pairs == PlateMath.defaultPairs)

        let model = PlateInventoryViewModel(prefs: prefs)
        model.setCount(2, for: 1.25)
        model.setCount(0, for: 25)
        model.setBar(text: "15")
        #expect(model.inventory.barKg == 15)
        #expect(!model.inventory.pairs.contains(25))
        #expect(model.inventory.pairs.filter { $0 == 1.25 }.count == 2)
        #expect(PlateInventoryStore.load(from: prefs) == model.inventory)

        model.setBar(text: "abc")   // invalid input never stores
        #expect(model.inventory.barKg == 15)
        #expect(model.barError != nil)
    }

    @Test func sizesRowsGroupPairsByPlateWithCounts() {
        let rows = PlateInventory(barKg: 20, pairs: [10, 5, 10, 1.25]).sizeRows
        #expect(rows.map(\.kg) == [10, 5, 1.25])
        #expect(rows.map(\.pairs) == [2, 1, 1])
    }
}
