/// W-B38-A A-9: the live-session heart-rate cap state, moved out of `SessionCoachViewModel`
/// (JIFeatures, which now delegates) so the iPhone logger and the Watch (W-B38-B) read one rule.
/// Port of `deriveHrCapState` (`mobile/src/lib/hrSafety.ts`). Plain ints — JICompute does not
/// import JICore, so the caller unpacks `GateSettings`.
public nonisolated enum SessionCap {
    public enum State: Sendable, Equatable { case unknown, under, approaching, breach, noLimit }

    public static let approachingBandBpm = 15

    /// The HR the session stays at or under: the cap and/or the top of Zone 4 when the user
    /// avoids Zone 5. nil = the user chose no limit at all.
    public static func limitBpm(hrCapBpm: Int?, zone5FloorBpm: Int?) -> Int? {
        [hrCapBpm, zone5FloorBpm.map { $0 - 1 }].compactMap { $0 }.min()
    }

    /// `nil` HR always reads as `.unknown`, never a false "under" all-clear.
    public static func state(hrBpm: Int?, limitBpm: Int?) -> State {
        guard let hrBpm else { return .unknown }
        guard let limitBpm else { return .noLimit }
        if hrBpm > limitBpm { return .breach }
        if hrBpm >= limitBpm - approachingBandBpm { return .approaching }
        return .under
    }

    public static func label(for state: State) -> String {
        switch state {
        case .unknown: "No live reading"
        case .noLimit: "No limit"
        case .under: "Under your limit"
        case .approaching: "Near your limit"
        case .breach: "OVER YOUR LIMIT"
        }
    }

    /// E15-5 port — every band ships one concrete next action. `zone5RangeText` non-nil = the
    /// user avoids Zone 5 (its range text, e.g. "171–185").
    public static func action(for state: State, limitBpm: Int?, zone5RangeText: String?) -> String {
        let limit = limitBpm.map(String.init) ?? "—"
        switch state {
        case .unknown: return "No live heart-rate reading for this session — pace/RPE only."
        case .noLimit: return "No heart-rate limit set — train by your plan and how you feel."
        case .under: return "On plan — hold pace."
        case .approaching: return "Within \(approachingBandBpm) bpm of your \(limit) limit — ease off before you reach it."
        case .breach:
            let zone5 = zone5RangeText.map { " You chose to stay out of Zone 5 (\($0))." } ?? ""
            return "Over your \(limit) limit — back off now." + zone5
        }
    }
}
