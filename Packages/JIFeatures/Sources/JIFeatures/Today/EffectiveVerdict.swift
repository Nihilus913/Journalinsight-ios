import Foundation
import JICore

/// W-B57b (B-62) — what Decide / Day / the summary line show once the user has overridden the
/// morning verdict. Pure: the caller passes the override only when it belongs to the verdict's
/// date (the hub already scopes `MorningResponse.verdictOverride` to `verdictDate`).
///
/// - no override / `accept` → the verdict itself, no caption;
/// - `full` / `modified` / `rest` → "FULL" / "MODIFIED" / "REST" + the override's session, and a
///   "was <VERDICT> · <reason>" caption when that is actually a change (a `modified` answer to a
///   MODIFIED verdict is not). With no verdict at all the caption is just the reason.
nonisolated public func effectiveVerdict(parts: VerdictParts, override: VerdictOverride?) -> (word: String, session: String, wasCaption: String?) {
    guard let override, override.choice != .accept else {
        let session = (override?.session).flatMap { $0.isEmpty ? nil : $0 } ?? parts.session
        return (parts.word, session, nil)
    }
    let word = overrideWord(override.choice)
    let session = override.session.isEmpty
        ? localOverrideSession(choice: override.choice, parts: parts, sessionForToday: nil)
        : override.session
    let reason = override.reason.flatMap { $0.isEmpty ? nil : $0 }
    let was = bareVerdictWord(parts)
    let caption: String?
    if parts.tone == .muted {
        caption = reason
    } else if was == word {
        caption = nil
    } else {
        caption = ["was \(was)", reason].compactMap { $0 }.joined(separator: " · ")
    }
    return (word, session, caption)
}

/// The tint for `effectiveVerdict`'s word: the verdict's own tone for no override / `accept`;
/// full = `.go`, modified = `.amber`, rest = `.muted`.
nonisolated public func effectiveVerdictTone(parts: VerdictParts, override: VerdictOverride?) -> VerdictTone {
    switch override?.choice {
    case nil, .accept?: parts.tone
    case .full?: .go
    case .modified?: .amber
    case .rest?: .muted
    }
}

/// The hub's `session` resolution (Wave Card Contract), for an override that is queued offline
/// and has no hub-resolved `session` yet: accept → the verdict's session; full →
/// `sessionForToday` (plan weekday) else the verdict's session; modified → the verdict's session
/// if the verdict was MODIFIED/REDUCED, else "Easy Z2 30–40 min"; rest → "Rest — walks only".
nonisolated public func localOverrideSession(choice: VerdictOverrideChoice, parts: VerdictParts, sessionForToday: String?) -> String {
    switch choice {
    case .accept:
        return parts.session
    case .full:
        if let s = sessionForToday, !s.isEmpty { return s }
        return parts.session
    case .modified:
        let bare = bareVerdictWord(parts)
        if (bare.hasPrefix("MODIFIED") || bare.hasPrefix("REDUCED")), !parts.session.isEmpty { return parts.session }
        return VerdictOverrideCopy.easySession
    case .rest:
        return VerdictOverrideCopy.restSession
    }
}

/// Hub-fixed strings (Wave Card Contract) + the effective words.
public nonisolated enum VerdictOverrideCopy {
    public static let easySession = "Easy Z2 30–40 min"
    public static let restSession = "Rest — walks only"
}

nonisolated private func overrideWord(_ choice: VerdictOverrideChoice) -> String {
    switch choice {
    case .accept: ""
    case .full: "FULL"
    case .modified: "MODIFIED"
    case .rest: "REST"
    }
}

/// `VerdictParts.word` keeps RN's parenthetical ("MODIFIED (HRV low)"); the caption wants the bare word.
nonisolated private func bareVerdictWord(_ parts: VerdictParts) -> String {
    parts.word.replacing(/\(.*\)/, with: "").trimmingCharacters(in: .whitespaces)
}
