import SwiftUI
import JICore
import JIDesign

/// Challenges screen (oracle: `app/challenges.tsx`), reached from `VerdictHeroView`'s challenges
/// link. Owns its own create/edit sheet presentation; the list body lives in
/// `ChallengesMirrorSection`.
public struct ChallengesView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // W7-L4: the hub being down must be visible on THIS screen too, not only Today.
                // Renders only once a fetch has landed and only while unreachable (see the banner's
                // own guard), so a first-ever load shows the spinner, not a scare.
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .error:
                    Surface {
                        VStack(spacing: 10) {
                            Text("Couldn't load challenges.").font(.footnote).foregroundStyle(JIColor.muted)
                            Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale)
                                .accessibilityLabel("Retry")
                                .accessibilityIdentifier("challenges-retry")
                        }
                    }
                case .empty, .loaded:
                    ChallengesMirrorSection(model: model, onEdit: { editing = .edit($0) })
                    newChallengeButton
                }
            }
            .padding(16)
        }
        .background(JIColor.bg)
        .navigationTitle("Challenges")
        .task { await model.load() }
        .sheet(item: $editing) { target in
            switch target {
            case .create:
                ChallengeEditor(model: ChallengeEditorViewModel(challenges: model), onSaved: { _ in })
            case .edit(let challenge):
                ChallengeEditor(model: ChallengeEditorViewModel(challenges: model, existing: challenge), onSaved: { _ in })
            }
        }
    }

    private var newChallengeButton: some View {
        Button {
            editing = .create
        } label: {
            Text("+ New challenge").frame(maxWidth: .infinity).padding()
                .background(JIColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(JIColor.text)
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("+ New challenge")
        .accessibilityIdentifier("challenges-new")
    }
}
