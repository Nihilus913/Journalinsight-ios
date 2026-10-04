/// W-B38-A A-9 (gap #28): which plates go on each side of the bar for a total load. Pure.
///
/// `pairs` is the plate INVENTORY, one element per PAIR the user owns (a repeated value = more
/// pairs of that size). The answer is the plates for ONE side, heaviest first, preferring the
/// heaviest plates that solve it exactly; `nil` when the load cannot be built from the inventory
/// (never a nearest guess — the screen says "not reachable with your plates").
public nonisolated enum PlateMath {
    /// Decision (Toby 2026-10-03): standard plates + the 1.25 / 2.5 kg microplates (09-28).
    /// Editable in the logger — this is only the first-launch inventory.
    public static let defaultPairs: [Double] = [25, 20, 15, 10, 10, 5, 5, 2.5, 2.5, 1.25, 1.25]
    /// A standard Olympic bar.
    public static let defaultBarKg: Double = 20

    static let toleranceKg = 0.001

    public static func perSide(totalKg: Double, barKg: Double, pairs: [Double]) -> [Double]? {
        guard totalKg.isFinite, barKg.isFinite, barKg > 0, totalKg >= barKg - toleranceKg else { return nil }
        return solve(side: (totalKg - barKg) / 2, pairs: pairs)
    }

    /// The exact plates (heaviest first) that make `side`, or nil. Never a nearest guess.
    static func solve(side: Double, pairs: [Double]) -> [Double]? {
        if side <= toleranceKg { return [] }
        let plates = pairs.filter { $0.isFinite && $0 > 0 }.sorted(by: >)
        var chosen: [Double] = []
        func search(_ start: Int, _ remaining: Double) -> Bool {
            if abs(remaining) <= toleranceKg { return true }
            var i = start
            while i < plates.count {
                let p = plates[i]
                if p <= remaining + toleranceKg {
                    chosen.append(p)
                    if search(i + 1, remaining - p) { return true }
                    chosen.removeLast()
                }
                // skip duplicates of the same size at this depth (same subtree)
                var j = i + 1
                while j < plates.count, abs(plates[j] - p) <= toleranceKg { j += 1 }
                i = j
            }
            return false
        }
        return search(0, side) ? chosen : nil
    }

    /// W-FIX13 F-3c — a dumbbell: `perHandKg` is the weight of ONE dumbbell, there is no bar, and
    /// each side of each dumbbell needs one plate, so a size counts once per two pairs in `pairs`
    /// (both hands are loaded from the same inventory). [] = an empty handle; nil = not loadable.
    public static func perSideDumbbell(perHandKg: Double, pairs: [Double]) -> [Double]? {
        guard perHandKg.isFinite, perHandKg >= 0 else { return nil }
        if perHandKg <= toleranceKg { return [] }
        let usable = pairs.filter { $0.isFinite && $0 > 0 }
        let perDumbbell = Dictionary(grouping: usable, by: { $0 })
            .flatMap { size, all in Array(repeating: size, count: all.count / 2) }
        return solve(side: perHandKg / 2, pairs: perDumbbell)
    }
}
