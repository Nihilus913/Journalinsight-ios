import SwiftUI

public nonisolated struct MacroRingValue: Sendable, Equatable {
    public let value: Double, goal: Double
    public init(value: Double, goal: Double) { self.value = value; self.goal = goal }
}

public nonisolated func macroRingsAccessibilityLabel(protein: MacroRingValue, carbs: MacroRingValue, fat: MacroRingValue) -> String {
    [("Protein", protein), ("Carbs", carbs), ("Fat", fat)]
        .map { "\($0.0) \(ringAccessibilityValue(value: $0.1.value, max: $0.1.goal)) grams" }
        .joined(separator: ", ")
}

/// §4b Fitness-style triple ring (64 pt): protein (info blue) outer, carbs (orange) middle,
/// fat (purple) inner — each vs its goal. Replaces the three progress bars in the macros card.
public struct MacroRings: View {
    let protein: MacroRingValue, carbs: MacroRingValue, fat: MacroRingValue
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiRevealAnimations) private var revealAnimations
    @State private var revealed = false

    /// Off for reduced motion and for snapshot renders (§8.5): the rings paint their FINAL value.
    private var animatesReveal: Bool { revealAnimations && !reduceMotion }

    public init(protein: MacroRingValue, carbs: MacroRingValue, fat: MacroRingValue) {
        self.protein = protein; self.carbs = carbs; self.fat = fat
    }

    public var body: some View {
        ZStack {
            ring(protein, tint: theme.color(.protein), inset: 0)   // W-FIX2: macro role, not the accent
            ring(carbs, tint: theme.color(.reduced), inset: 1)
            ring(fat, tint: theme.color(.sleep), inset: 2)
        }
        .frame(width: size, height: size)
        .onAppear { if animatesReveal { withAnimation(JIMotion.standard) { revealed = true } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macroRingsAccessibilityLabel(protein: protein, carbs: carbs, fat: fat))
    }

    private func ring(_ m: MacroRingValue, tint: Color, inset: Int) -> some View {
        let lineWidth = size * 0.11
        let diameter = size - CGFloat(inset) * 2 * (lineWidth + 2)
        let fraction = ringFraction(value: m.value, max: m.goal)
        return ZStack {
            Circle().stroke(theme.color(.nested), lineWidth: lineWidth)
            Circle().trim(from: 0, to: (revealed || !animatesReveal) ? fraction : 0)
                .stroke(
                    AngularGradient(stops: ringFadeStops(tint), center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * fraction)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}
