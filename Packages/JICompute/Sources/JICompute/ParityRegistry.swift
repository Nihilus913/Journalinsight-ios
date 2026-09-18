/// Parity registry (R6b-8): source-of-truth classification per metric.
///
/// Verbatim port of the RN oracle `mobile/src/compute/shared/parityRegistry.ts`
/// (frozen v1.18.2). Every metric the hub (the FastAPI backend) computes or
/// serves is classified here as one of:
///
///   - `.hub`      : Python computes it; the app reads the hub's value as-is.
///                   No local recomputation exists or is planned.
///   - `.computed` : the app has a ported implementation that must reproduce
///                   the hub's number exactly (a "parity port" — see
///                   `docs/superpowers/specs/2026-08-23-ts-compute-parity-port`).
///                   Golden-fixture + replay-diff validation (`scripts/parity/`)
///                   is required before the local value is trusted for anything
///                   beyond display.
///   - `.hubOnly`  : the app deliberately does NOT (and, per standing decision,
///                   will not) recompute this locally — either because the
///                   source value is a third-party black box (Garmin's own
///                   proprietary algorithm; there is no independently verifiable
///                   "equivalent digit" to reproduce), or because a later wave
///                   is scheduled to add a local write surface for it and it is
///                   pre-registered here ahead of that work.
///
/// Any metric NOT listed here defaults to `.hub` — the safe default, since it
/// means "nothing here claims local parity; trust the server."
///
/// Mirrors: `app/shared/parity_registry.py` and the TS file above carry the same
/// key set and the same source/notes values. The three cannot import each other
/// across the language boundary, so keep them in sync by hand — update all
/// three in the same commit.
///
/// Tool: `scripts/parity/replay_diff.py` diffs a hub-sourced JSON export against
/// a computed/local one for any metric registered here.
/// Guard: `tests/test_parity_registry.py`.
public nonisolated enum ParitySource: String, Sendable, Equatable, CaseIterable {
    case hub
    case computed
    case hubOnly = "hub-only"
}

public nonisolated struct ParityEntry: Sendable, Equatable {
    public let source: ParitySource
    public let notes: String

    public init(source: ParitySource, notes: String) {
        self.source = source
        self.notes = notes
    }
}

public nonisolated enum ParityRegistry {
    public static let defaultSource: ParitySource = .hub

    public static let entries: [String: ParityEntry] = [
        // --- R6b-1: sleep score parity port ----------------------------------
        "sleep_score_computed": ParityEntry(
            source: .computed,
            notes: "R6b-1: ported sleep-score algorithm; golden fixture gen_golden_sleep.py + mobile sleep.parity.test.ts."
        ),
        "sleep_debt": ParityEntry(
            source: .computed,
            notes: "R6b-1: rolling sleep-debt computation ported to TS; must match core.sleep_debt (F6-2) bit-for-bit."
        ),
        "bedtime_consistency_sd": ParityEntry(
            source: .computed,
            notes: "R6b-1: bedtime-consistency standard deviation ported to TS alongside the sleep score."
        ),

        // --- R6b-5: readiness composite --------------------------------------
        "readiness_categorical": ParityEntry(
            source: .computed,
            notes: "R6b-5: ranking-grade categorical readiness composite (app/vitals/readiness_composite.py); ordinal parity only (rank agreement), not exact-digit parity."
        ),
        "readiness_hub_input_2_2": ParityEntry(
            source: .hubOnly,
            notes: "One of readiness_categorical's raw hub inputs (input 2 of 2); fetched from the hub, never recomputed locally."
        ),

        // --- established hub-computed / hub-only vitals -----------------------
        "rhr": ParityEntry(
            source: .hub,
            notes: "Resting heart rate; hub-computed, read as-is."
        ),
        "hrv": ParityEntry(
            source: .hubOnly,
            notes: "Decision #23 (plan's Toby decision sheet): HRV is Garmin's own proprietary reading, no independently verifiable local equivalent exists -- always read the hub's value, never approximate it in mobile."
        ),
        "vo2max": ParityEntry(
            source: .hub,
            notes: "VO2max; hub-computed (Garmin-derived), read as-is."
        ),
        "body_battery": ParityEntry(
            source: .hubOnly,
            notes: "Garmin proprietary Body Battery; hub-only until F5c-I's R6b-6b lands a local approximation."
        ),
        "trimp_load": ParityEntry(
            source: .hub,
            notes: "TRIMP training load; hub-computed, read as-is."
        ),

        // --- R6c-6 local-first write surfaces (F5b/R6d-1 implements later) ----
        // Pre-registered ahead of implementation so the registry stays
        // forward-complete; F5b's R6d-1 will flip each of these to its actual
        // per-metric source once the local-first write path lands.
        "exercise_strength_state": ParityEntry(
            source: .hub,
            notes: "R6c-6 local-first write surface (exercise strength state); pre-registered ahead of F5b/R6d-1, which will flip this per-metric."
        ),
        "gate_respond": ParityEntry(
            source: .hub,
            notes: "R6c-6 local-first write surface (gate respond); pre-registered ahead of F5b/R6d-1, which will flip this per-metric."
        ),
        "session_feel": ParityEntry(
            source: .hub,
            notes: "R6c-6 local-first write surface (session feel); pre-registered ahead of F5b/R6d-1, which will flip this per-metric."
        ),
        "weigh_in": ParityEntry(
            source: .hub,
            notes: "R6c-6 local-first write surface (weigh-in); pre-registered ahead of F5b/R6d-1, which will flip this per-metric."
        ),
        "nutrition_log_redirect": ParityEntry(
            source: .hub,
            notes: "R6c-6 local-first write surface (nutrition log redirect); pre-registered ahead of F5b/R6d-1, which will flip this per-metric."
        ),
    ]

    /// Return the parity source for `metric`, defaulting to `.hub`.
    public static func source(for metric: String) -> ParitySource {
        entries[metric]?.source ?? defaultSource
    }

    /// Return the full entry for `metric`.
    ///
    /// Metrics not in the registry default to `.hub` with a generic note.
    public static func entry(for metric: String) -> ParityEntry {
        entries[metric] ?? ParityEntry(source: defaultSource, notes: "not registered; defaults to hub.")
    }
}
