import Foundation
import SwiftUI
import Testing
@testable import JIFeatures

// W-FIX11 H2-07 (bug hunt 2026-10-01): at AX3, Settings › Targets › Calories clipped "Daily goal ·
// kcal" / "Wanted deficit · kcal/day" at the card's left edge and the + at its right edge (field
// x=6.7 … + at x=395 in a 16–386 card). Every stepper row fits the card's width.

#if canImport(UIKit)
@Test @MainActor func targetStepperRowsFitTheCardAtAX3() {
    // iPhone 18 Pro portrait (402 pt) minus the inset-grouped form margins and row padding.
    let width: CGFloat = 402 - 2 * 16 - 2 * 20
    for size in [DynamicTypeSize.large, .accessibility1, .accessibility3, .accessibility5] {
        for (title, unit) in [("Daily goal", "kcal"), ("Wanted deficit", "kcal/day"), ("Weekly floor", "kcal")] {
            let row = TargetStepperField(title: title, text: .constant("2,117"), unit: unit, step: 50, decimals: 0,
                                         fallback: nil, id: "goal")
                .environment(\.dynamicTypeSize, size)
            let fitted = UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            #expect(fitted.width <= width + 0.5, "\(size) \(title): the row is \(fitted.width) pt wide in a \(width) pt card")
        }
    }
}
#endif
