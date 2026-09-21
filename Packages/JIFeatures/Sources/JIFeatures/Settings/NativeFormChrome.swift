import SwiftUI
import JIDesign

/// B-33 §5 + §8.2 chrome for the `List`/`Form` screens this lane owns (L6). The explicit
/// the explicit page backgrounds are gone, so the **system grouped background** shows through; the
/// only thing a screen still has to say is "inset grouped", and that style does not exist on
/// macOS (the host the package tests run on), hence the one `#if` here instead of ~15 inline.
///
/// Named for the lane so a parallel Phase-B lane adding its own chrome helper cannot collide.
extension View {
    /// `.listStyle(.insetGrouped)` where the platform has it, a no-op where it does not.
    ///
    /// **`List` only.** A `Form` is already inset grouped on iOS, and forcing the style onto one
    /// deadlocks `ImageRenderer` at accessibility text sizes — the §8.5 sweep hangs instead of
    /// failing (bisected on `CheckInSheet`, B-33 L6). The `Form` screens in this lane therefore
    /// carry no style modifier at all; they only drop their explicit page background (§5).
    func jiNativeFormChrome() -> some View {
        #if os(iOS) || os(visionOS)
        return self.listStyle(.insetGrouped)
        #else
        return self
        #endif
    }

    /// §8.2: sheets are form-sized in regular width instead of full-screen.
    func jiNativeSheetSizing() -> some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        return self.presentationSizing(.form)
        #else
        return self
        #endif
    }
}
