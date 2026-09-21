import SwiftUI
import JIDesign

/// §8.5 registry entry "Weekly plan". `WeeklyPlanStore(prefs: nil)` is the store's own
/// no-database path — it yields the documented default knobs, so the sweep shows the real table.
struct WeeklyPlanNativePreview: View {
    @State private var model = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: nil))

    var body: some View {
        VStack {
            WeeklyPlanView(model: model).nativeContent
                .padding(.horizontal, 20).padding(.top, 8)
                .readableColumn()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JITheme.native.color(.bg))
    }
}
