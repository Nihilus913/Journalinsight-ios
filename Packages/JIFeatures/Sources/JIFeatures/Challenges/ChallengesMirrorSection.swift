import SwiftUI
import JICore
import JIDesign

/// The Active/Past challenge list (oracle: `app/challenges.tsx`'s two `.map` blocks over
/// `ChallengeCard`). Named to match the RN component family (`ChallengesMirrorSection.tsx`) that
/// this screen's list rendering corresponds to; unlike the oracle's read-only local-first mirror
/// widget, this is the full CRUD screen's own list (no separate offline-mirror store this lane —
/// not in L3's `consumes`), so "mirror" here means "renders the current `ChallengesViewModel`
/// rows," not a second local cache.
public struct ChallengesMirrorSection: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: ChallengesViewModel
    let onEdit: (GateChallenge) -> Void

    public init(model: ChallengesViewModel, onEdit: @escaping (GateChallenge) -> Void) {
        self.model = model; self.onEdit = onEdit
    }

    /// §2b.2: Active / Past are real `List` sections with system headers; each challenge is one
    /// row. Callers put this straight into a `List`.
    @ViewBuilder
    public var body: some View {
        Section("Active") {
            if model.active.isEmpty {
                Text("No active challenge right now.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            } else {
                ForEach(model.active) { challenge in
                    ChallengeCard(challenge: challenge, model: model, onEdit: { onEdit(challenge) })
                }
            }
        }
        if !model.past.isEmpty {
            Section("Past") {
                ForEach(model.past) { challenge in
                    ChallengeCard(challenge: challenge, model: model, onEdit: { onEdit(challenge) })
                }
            }
        }
    }
}

/// One challenge row (oracle: `ChallengeCard`). Owns its own archive/delete confirm dialogs and
/// menu-expand state — the list above stays a pure `ForEach` over `ChallengesViewModel.challenges`.
struct ChallengeCard: View {
    @Environment(\.jiTheme) private var theme
    let challenge: GateChallenge
    @Bindable var model: ChallengesViewModel
    let onEdit: () -> Void

    @State private var dialog: DialogKind?
    @State private var completeNote = ""
    @State private var actionError: String?
    @State private var isBusy = false

    private enum DialogKind: Identifiable { case complete, archive, delete
        var id: Self { self }
    }

    private static let statusLabel: [ChallengeStatus: String] = [.active: "Active", .completed: "Completed", .archived: "Archived"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(challenge.title).jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                Spacer(minLength: 8)
                Text(Self.statusLabel[challenge.status] ?? "")
                    .jiFont(.micro, weight: .bold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(challenge.status == .active ? theme.color(.reduced) : theme.color(.control), in: Capsule())
                    .foregroundStyle(challenge.status == .active ? theme.color(.bg) : theme.color(.text))
                actionsMenu
            }
            Text(challenge.hypothesis).jiFont(.footnote).foregroundStyle(theme.color(.muted)).lineLimit(3)
            Text("Started \(challenge.startDate) · \(challenge.sessionFilter) sessions")
                .jiFont(.micro).foregroundStyle(theme.color(.muted))

            scoreChip
            progressBar

            if let note = challenge.resultNote, !note.isEmpty {
                Text("Result: \(note)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
            if let actionError { Text(actionError).jiFont(.micro).foregroundStyle(theme.color(.danger)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .swipeActions(edge: .trailing) {
            if challenge.canDelete {
                Button("Delete", role: .destructive) { dialog = .delete }
                    .accessibilityLabel("Delete \(challenge.title)")
            }
            if challenge.status == .active {
                Button("Archive") { dialog = .archive }
                    .accessibilityLabel("Archive \(challenge.title)")
            }
        }
        .confirmationDialog("Complete this challenge?", isPresented: isPresented(.complete), titleVisibility: .visible) {
            Button("Mark complete") { runArchive(status: .completed) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" is at \(challenge.progress.count) of \(challenge.progress.target) sessions. Completing now locks in today's score.")
        }
        .confirmationDialog("Archive this challenge?", isPresented: isPresented(.archive), titleVisibility: .visible) {
            Button("Archive") { runArchive(status: .archived) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" moves to Archived. Its progress and score stay on record.")
        }
        .confirmationDialog("Delete this challenge?", isPresented: isPresented(.delete), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { runDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" has no recorded sessions yet — this can't be undone.")
        }
        .disabled(isBusy)
    }

    /// The bespoke expand-in-place list became the system `Menu` (§2b.2 — iOS row idiom).
    private var actionsMenu: some View {
        Menu {
            Button("Edit") { onEdit() }
                .accessibilityLabel("Edit \(challenge.title)")
                .accessibilityIdentifier("challenge-card-edit")
            if challenge.status == .active {
                Button("Mark complete") { completeNote = challenge.resultNote ?? ""; dialog = .complete }
                    .accessibilityLabel("Mark \(challenge.title) complete")
                    .accessibilityIdentifier("challenge-card-complete")
                Button("Archive") { dialog = .archive }
                    .accessibilityLabel("Archive \(challenge.title)")
                    .accessibilityIdentifier("challenge-card-archive")
            }
            if challenge.canDelete {
                Button("Delete", role: .destructive) { dialog = .delete }
                    .accessibilityLabel("Delete \(challenge.title)")
                    .accessibilityIdentifier("challenge-card-delete")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("\(challenge.title) actions")
        .accessibilityIdentifier("challenge-card-actions")
    }

    private func isPresented(_ kind: DialogKind) -> Binding<Bool> {
        Binding(get: { dialog == kind }, set: { if !$0 { dialog = nil } })
    }

    private func runArchive(status: ChallengeArchiveStatus) {
        let note = completeNote.trimmingCharacters(in: .whitespaces)
        Task {
            isBusy = true
            switch await model.archive(challengeId: challenge.challengeId, status: status, resultNote: note.isEmpty ? nil : note) {
            case .success: actionError = nil
            case .failure(let err): actionError = describeChallengeMutationError(err)
            }
            isBusy = false
        }
    }

    private func runDelete() {
        Task {
            isBusy = true
            if let err = await model.delete(challengeId: challenge.challengeId) {
                actionError = describeChallengeMutationError(err)
            }
            isBusy = false
        }
    }

    /// Oracle `ScoreChip`: plain neutral chip, never a verdict hue (FROZEN CONTRACT §2.4).
    private var scoreChip: some View {
        let sentence = challenge.status == .completed
            ? "Finished \(challenge.progress.count) of \(challenge.progress.target) (\(challenge.progress.executionScore)%)"
            : "\(challenge.progress.count) of \(challenge.progress.target) sessions, \(paceLabel)"
        return HStack(spacing: 8) {
            Text("\(challenge.progress.executionScore)%")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(theme.color(.surface2), in: Capsule())
                .foregroundStyle(theme.color(.text))
                .opacity(challenge.status == .archived ? 0.55 : 1)
            Text(sentence).font(.caption).foregroundStyle(theme.color(.muted))
                .accessibilityLabel(sentence)
                .accessibilityIdentifier("challenge-card-score")
        }
    }

    private var paceLabel: String {
        switch challenge.progress.pace {
        case "ahead": "ahead of pace"
        case "behind": "behind pace"
        default: "on pace"
        }
    }

    /// §8.1: no fixed geometry — the system bar fills whatever width the row gets.
    private var progressBar: some View {
        ProgressView(value: challenge.progress.target > 0
            ? min(1, max(0, Double(challenge.progress.count) / Double(challenge.progress.target))) : 0)
            .tint(theme.color(.reduced))
            .accessibilityLabel("\(challenge.title) progress")
            .accessibilityValue("\(challenge.progress.count) of \(challenge.progress.target) sessions")
        .accessibilityIdentifier("challenge-card-progress")
    }
}
