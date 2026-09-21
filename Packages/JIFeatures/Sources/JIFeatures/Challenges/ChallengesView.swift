import SwiftUI
import JICore
import JIDesign

/// Challenges screen (oracle: `app/challenges.tsx`), reached from `VerdictHeroView`'s challenges
/// link. Owns its own create/edit sheet presentation; the list body lives in
/// `ChallengesMirrorSection`.
public struct ChallengesView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: ChallengesViewModel
    @State private var editing: EditingTarget?

    private enum EditingTarget: Identifiable {
        case create
        case edit(GateChallenge)
        var id: String {
            switch self { case .create: "create"; case .edit(let c): "edit-\(c.challengeId)" }
        }
    }

    public init(model: ChallengesViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            // W7-L4: the hub being down must be visible on THIS screen too, not only Today.
            // Renders only once a fetch has landed and only while unreachable (see the banner's
            // own guard), so a first-ever load shows the spinner, not a scare.
            if !model.hubReachable, model.fetchedAt != nil {
                Section { StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable) }
            }
            switch model.phase {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .error:
                Section {
                    Text("Couldn't load challenges.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    Button("Retry") { Task { await model.refresh() } }
                        .accessibilityLabel("Retry")
                        .accessibilityIdentifier("challenges-retry")
                }
            case .empty, .loaded:
                ChallengesMirrorSection(model: model, onEdit: { editing = .edit($0) })
                Section {
                    Button("New challenge", systemImage: "plus") { editing = .create }
                        .accessibilityLabel("+ New challenge")
                        .accessibilityIdentifier("challenges-new")
                }
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Challenges")
        .task { await model.load() }
        .sheet(item: $editing) { target in
            switch target {
            case .create:
                ChallengeEditor(model: ChallengeEditorViewModel(challenges: model), onSaved: { _ in })
                    .jiNativeSheetSizing()
            case .edit(let challenge):
                ChallengeEditor(model: ChallengeEditorViewModel(challenges: model, existing: challenge), onSaved: { _ in })
                    .jiNativeSheetSizing()
            }
        }
    }
}
