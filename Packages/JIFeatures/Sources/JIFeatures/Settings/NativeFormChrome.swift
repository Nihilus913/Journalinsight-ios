import SwiftUI
import JIDesign

/// B-33 §5 + §8.2 chrome for the `List`/`Form` screens this lane owns (L6). The explicit
/// `JIColor.bg` backgrounds are gone, so the **system grouped background** shows through; the
/// only thing a screen still has to say is "inset grouped", and that style does not exist on
/// macOS (the host the package tests run on), hence the one `#if` here instead of ~15 inline.
///
/// Named for the lane so a parallel Phase-B lane adding its own chrome helper cannot collide.
extension View {
    /// `.listStyle(.insetGrouped)` where the platform has it, a no-op where it does not.
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
