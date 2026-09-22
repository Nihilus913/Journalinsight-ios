import SwiftUI
import JICore
import JIPersistence
import JIDesign

/// §8.5 registry entry "Weigh-in". In-memory outbox + a fixture provider: the sweep never writes
/// to the real database and never pushes a weight to Garmin.
private struct L5WeighInProvider: WeighInProviding {
    func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult { throw HubError.unauthorized }
}

struct WeighInNativePreview: View {
    @State private var model: WeighInViewModel?

    /// Built in `init`, not `onAppear`: `ImageRenderer` runs neither `.task` nor `.onAppear`, so a
    /// lazily-built model would leave the sweep photographing an empty placeholder.
    init() {
        _model = State(initialValue: (try? AppDatabase.inMemory()).map {
            WeighInViewModel(outbox: Outbox(db: $0), provider: L5WeighInProvider())
        })
    }

    var body: some View {
        Group {
            if let model {
                WeighInSheet(model: model).nativeContent
            } else {
                // `AppDatabase.inMemory()` can throw; rule 5 — say so rather than draw a blank.
                Text("No database").jiFont(.footnote).foregroundStyle(JITheme.native.color(.muted))
            }
        }
        .jiTheme(.native)
        .background(JITheme.native.color(.bg))
    }
}
