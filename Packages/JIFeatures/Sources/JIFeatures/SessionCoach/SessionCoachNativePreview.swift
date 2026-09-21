import SwiftUI
import JIDesign

/// §8.5 registry entry "Session coach". `SessionCoachViewModel(provider: nil)` is the real,
/// shipping "no live HR source" state — the screen's honest wall (rule 5), not a faked reading.
struct SessionCoachNativePreview: View {
    @State private var model = SessionCoachViewModel(provider: nil)

    var body: some View {
        VStack {
            SessionCoachView(model: model).nativeContent
                .padding(.horizontal, 20).padding(.top, 8)
                .readableColumn()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JITheme.native.color(.bg))
    }
}
