import SwiftUI
extension View {
    /// `.keyboardType` is iOS-only; `swift test` builds for the macOS host. `.numbersAndPunctuation`
    /// lets the user type a minus sign — the number is theirs.
    @ViewBuilder func numberPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
