import Foundation
import JICore
import JICompute

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
    // W-FIX1 BUG-27: the caption speaks the user's words ("was Modified"), never the hub's GO.
    let was = verdictUserWord(parts)
    let caption: String?
    if parts.tone == .muted {
        caption = reason
    } else if was == verdictUserWord({ var p = parts; p.word = word; return p }()) {
        caption = nil
    } else {
        caption = ["was \(was)", reason].compactMap { $0 }.joined(separator: " · ")
    }
    return (word, session, caption)
}

/// The tint for `effectiveVerdict`'s word: the verdict's own tone for no override / `accept`
/// (amber for the hub's auto-regulated GO — W-FIX1 BUG-03); full = `.go`, modified = `.amber`,
/// rest = `.muted`.
nonisolated public func effectiveVerdictTone(parts: VerdictParts, override: VerdictOverride?) -> VerdictTone {
    switch override?.choice {
    case nil, .accept?: displayVerdictParts(parts).tone
    case .full?: .go
    case .modified?: .amber
    case .rest?: .muted
    }
}

/// The hub's `session` resolution (Wave Card Contract), for an override that is queued offline
/// and has no hub-resolved `session` yet: accept → the verdict's session; full →
/// `sessionForToday` (plan weekday) else the verdict's session; modified → the trimmed prescription
/// on an amber auto-regulated GO, the verdict's session if the verdict was MODIFIED/REDUCED, else
/// "Easy Z2 30–40 min"; rest → "Rest — walks only".
nonisolated public func localOverrideSession(choice: VerdictOverrideChoice, parts: VerdictParts, sessionForToday: String?) -> String {
    switch choice {
    case .accept:
        return parts.session
    case .full:
        if let s = sessionForToday, !s.isEmpty { return s }
        return parts.session
    case .modified:
        // W-FIX1 BUG-03: on the hub's amber day the Modified session IS the trimmed prescription
        // (the hub's `modified_session_for` resolves the same), never the generic easy Z2.
        if let trimmed = autoRegulatedPrescription(parts) { return trimmed }
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

// MARK: - B-57 W1 r5: the user-facing verdict word (one source of truth)

/// The three words the boards show for the morning call (Decide, GateRationale, its Last 3 days
/// table, GateConfig's "How the morning call works" card).
public nonisolated enum VerdictUserWord {
    public static let full = "Full"
    public static let modified = "Modified"
    public static let rest = "Rest"
}

/// The hub's verdict word ("GO", "REDUCED (sleep)", "RED", or an override's "FULL" / "MODIFIED" /
/// "REST") as the user reads it: GO/FULL → Full, REDUCED/MODIFIED → Modified, RED/REST → Rest.
/// The parenthetical is dropped (the reason lives in the Why rows). No verdict stays "—"; a word the
/// map does not know is shown as sent, never guessed.
public nonisolated func verdictUserWord(_ parts: VerdictParts) -> String {
    let bare = bareVerdictWord(parts)
    guard !bare.isEmpty else { return parts.word }
    let upper = bare.uppercased()
    // W-FIX1 BUG-03: "GO (auto-regulated)" is the hub's amber day — a trimmed session, so the
    // user reads Modified (RN `verdict.ts` keeps the qualifier; dropping it made amber read Full).
    if isAutoRegulated(parts) { return VerdictUserWord.modified }
    if upper.hasPrefix("GO") || upper.hasPrefix("FULL") { return VerdictUserWord.full }
    if upper.hasPrefix("REDUCED") || upper.hasPrefix("MODIFIED") { return VerdictUserWord.modified }
    if upper.hasPrefix("RED") || upper.hasPrefix("REST") { return VerdictUserWord.rest }
    return bare
}

// MARK: - W-FIX1 BUG-03: the hub's amber auto-regulation

/// `morning_go.evaluate`'s amber GO: "GO (auto-regulated) — <session>". The day is still trained,
/// but trimmed (see `autoRegulatedPrescription`).
public nonisolated func isAutoRegulated(_ parts: VerdictParts) -> Bool {
    let head = parts.word.lowercased()
    return head.hasPrefix("go") && head.contains("auto-regulated")
}

/// The verdict as every screen tints it: the hub's auto-regulated GO is amber (Modified), not the
/// green of a full GO. Word and session are unchanged (the word map is `verdictUserWord`).
public nonisolated func displayVerdictParts(_ parts: VerdictParts) -> VerdictParts {
    guard isAutoRegulated(parts) else { return parts }
    var out = parts
    out.tone = .amber
    return out
}

/// The reduced prescription of an auto-regulated day, or nil for any other verdict.
///
/// Prefers the hub's own persisted reason (`/planning/morning-verdict` `reason`,
/// "Amber (<why>): <what to do>.") — the text after the amber clause. Without it (Today's
/// `/morning` carries no reason) it is the hub's fixed amber instruction for the planned session's
/// type, looked up by name in `sessionByWeekday` (the same table `evaluate` reads): strength →
/// "lift … 1-2 reps shy of failure; trim Z2 to ~25min or walk", long Z2 → "cap the long run at
/// ~45min easy, or walk it". A session name the table does not know gets nil — never guessed.
public nonisolated func autoRegulatedPrescription(_ parts: VerdictParts, reason: String? = nil) -> String? {
    guard isAutoRegulated(parts) else { return nil }
    if let reason, let range = reason.range(of: "): ") {
        let tail = reason[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { return capitalizedFirst(tail) }
    }
    switch sessionByWeekday.first(where: { $0.name == parts.session })?.type {
    case .strength?: return AutoRegulatedCopy.strength
    case .z2?: return AutoRegulatedCopy.longZ2
    default: return nil
    }
}

/// Why the hub auto-regulated ("overnight vitals not synced yet", "HRV 23, RHR 66") — the amber
/// clause of the persisted reason, or nil when there is none.
public nonisolated func autoRegulatedWhy(_ parts: VerdictParts, reason: String?) -> String? {
    guard isAutoRegulated(parts), let reason,
          let m = reason.firstMatch(of: /^Amber \((.*?)\):/) else { return nil }
    let why = String(m.1).trimmingCharacters(in: .whitespaces)
    return why.isEmpty ? nil : why
}

/// `morning_go.evaluate`'s amber instructions (`MorningGateGate.swift`, verbatim but sentence-cased).
public nonisolated enum AutoRegulatedCopy {
    public static let strength = "Lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk."
    public static let longZ2 = "Cap the long run at ~45min easy, or walk it."
}

nonisolated private func capitalizedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.uppercased() + s.dropFirst()
}
