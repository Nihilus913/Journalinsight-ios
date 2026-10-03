import JICore
import JIDesign

/// B-33: the verdict tone → semantic role map (the theme-aware twin of the classic tone helper). The
/// reserved set is unchanged — go/amber/red/muted → go/reduced/danger/muted (rule 6).
public nonisolated func verdictColorRole(_ tone: VerdictTone) -> JIColorRole {
    switch tone { case .go: .go; case .amber: .reduced; case .red: .danger; case .muted: .muted }
}
