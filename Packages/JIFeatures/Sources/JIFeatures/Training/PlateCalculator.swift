import Foundation
import Observation
import JICompute
import JIPersistence

/// W-B38-B B-9 — the user's bar + plate pairs (Settings › Plates & bar). First launch = the
/// standard set + Toby's 1.25 / 2.5 kg microplates (decision 2026-10-03, `PlateMath.defaultPairs`);
/// an emptied inventory means "no calculator" (scout §4 q2).
public nonisolated struct PlateInventory: Codable, Equatable, Sendable {
    public var barKg: Double
    /// One element per PAIR owned (a repeated size = more pairs of it).
    public var pairs: [Double]

    public init(barKg: Double, pairs: [Double]) { self.barKg = barKg; self.pairs = pairs }

    public static let standard = PlateInventory(barKg: PlateMath.defaultBarKg, pairs: PlateMath.defaultPairs)

    public var canCalculate: Bool { barKg > 0 && !pairs.isEmpty }

    public struct SizeRow: Equatable, Sendable, Identifiable {
        public let kg: Double
        public let pairs: Int
        public var id: Double { kg }
    }

    /// Distinct plate sizes heaviest first, with how many pairs of each.
    public var sizeRows: [SizeRow] {
        Dictionary(grouping: pairs, by: { $0 }).map { SizeRow(kg: $0.key, pairs: $0.value.count) }.sorted { $0.kg > $1.kg }
    }
}

public nonisolated enum PlateInventoryStore {
    public static let key = "strength.plates.v1"

    /// The saved inventory; the standard set when nothing (or nothing readable) is saved.
    public static func load(from prefs: PrefStore) -> PlateInventory {
        ((try? prefs.get(key, as: PlateInventory.self)) ?? nil) ?? .standard
    }

    public static func save(_ inventory: PlateInventory, to prefs: PrefStore) throws { try prefs.set(key, inventory) }
}

/// The sheet's model: which plates go on each side for `totalKg`. Never a nearest guess.
@Observable @MainActor
public final class PlateCalculatorViewModel {
    public enum Outcome: Equatable, Sendable {
        case plates([Double])
        case barOnly
        case notLoadable
        case noInventory
    }

    public let totalKg: Double
    public let inventory: PlateInventory

    public init(totalKg: Double, inventory: PlateInventory) {
        self.totalKg = totalKg
        self.inventory = inventory
    }

    public var outcome: Outcome {
        guard inventory.canCalculate else { return .noInventory }
        guard let side = PlateMath.perSide(totalKg: totalKg, barKg: inventory.barKg, pairs: inventory.pairs) else { return .notLoadable }
        return side.isEmpty ? .barOnly : .plates(side)
    }

    public var headline: String { "\(kgText(totalKg)) kg on a \(kgText(inventory.barKg)) kg bar" }

    public var perSideText: String {
        switch outcome {
        case .plates(let side): side.map(kgText).joined(separator: " + ") + " kg each side"
        case .barOnly: "Just the bar"
        case .notLoadable: "\(kgText(totalKg)) kg is not loadable with your plates"
        case .noInventory: "Add your plates in Settings › Plates & bar"
        }
    }
}

/// Settings › Plates & bar editor model.
@Observable @MainActor
public final class PlateInventoryViewModel {
    public private(set) var inventory: PlateInventory
    public private(set) var barError: String?
    public private(set) var saveError: String?
    private let prefs: PrefStore

    public init(prefs: PrefStore) {
        self.prefs = prefs
        inventory = PlateInventoryStore.load(from: prefs)
    }

    public func setCount(_ count: Int, for kg: Double) {
        var pairs = inventory.pairs.filter { $0 != kg }
        pairs += Array(repeating: kg, count: max(0, count))
        inventory.pairs = pairs.sorted(by: >)
        persist()
    }

    /// Adds a new plate size (one pair); ignores non-positive or unreadable input.
    @discardableResult public func addSize(text: String) -> Bool {
        guard let kg = parseKg(text), kg > 0 else { return false }
        setCount((inventory.sizeRows.first { $0.kg == kg }?.pairs ?? 0) + 1, for: kg)
        return true
    }

    public func setBar(text: String) {
        guard let kg = parseKg(text), kg > 0 else { barError = "Enter the bar's weight in kg."; return }
        barError = nil
        inventory.barKg = kg
        persist()
    }

    public func resetToStandard() {
        inventory = .standard
        persist()
    }

    private func persist() {
        do { try PlateInventoryStore.save(inventory, to: prefs); saveError = nil }
        catch { saveError = "Couldn't save your plates." }
    }
}

nonisolated func parseKg(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard let v = Double(t), v.isFinite else { return nil }
    return v
}

/// 52.5 → "52.5", 20 → "20", 1.25 → "1.25".
nonisolated func kgText(_ kg: Double) -> String {
    if kg == kg.rounded() { return String(Int(kg)) }
    var s = String(format: "%.2f", kg)
    while s.hasSuffix("0") { s.removeLast() }
    return s
}
