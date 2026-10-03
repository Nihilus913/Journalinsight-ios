// W-DEAD-2 D2-9: gallery/preview support — compiled into Debug only, never the installed app.
#if DEBUG
import SwiftUI
import JIDesign

/// §8.5 registry entry "Session coach". `SessionCoachViewModel(provider: nil)` is the real,
/// shipping "no live HR source" state — the screen's honest wall (rule 5), not a faked reading.
/// B-57 W4: shown with the migrated pre-W4 settings so the gallery draws the cap layout (the
/// no-cap layout is pinned by `noCapMeansNoCapCopy`).
struct SessionCoachNativePreview: View {
    @State private var model = SessionCoachViewModel(provider: nil, settings: .legacyPreW4)

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
#endif
