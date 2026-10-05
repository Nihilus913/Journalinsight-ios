import Foundation

/// B-44 Option B (Toby 2026-10-04, "(4) REVISED"): the phone's own morning verdict, uploaded each
/// morning so the hub stores it beside its own `plan.morning_verdict` row for the same date
/// (`plan.ondevice_verdict`, HT migration 077). Offline-first: queued in the `Outbox` (kind
/// `OnDeviceVerdictUpload.outboxKind`) and replayed by `OutboxDrainer`.
public protocol OnDeviceVerdictUploading: Sendable {
    /// `POST /api/v1/planning/ondevice-verdict` — upsert per `date`.
    func uploadOnDeviceVerdict(_ body: OnDeviceVerdictUpload) async throws -> OnDeviceVerdictStored
}

/// The wire body. Keys are the hub's snake_case spelling (`HubClient.send` encodes as-is), and the
/// same encoding is the outbox payload.
public struct OnDeviceVerdictUpload: Codable, Sendable, Equatable {
    public static let outboxKind = "ondevice_verdict"

    public var date: String
    public var verdict: String
    public var reason: String?
    public var sessionPrescription: String?
    public var baselineNights: Int?
    public var inputsDigest: String?
    /// ISO-8601.
    public var computedAt: String?

    public init(date: String, verdict: String, reason: String?, sessionPrescription: String?,
                baselineNights: Int?, inputsDigest: String?, computedAt: String?) {
        self.date = date; self.verdict = verdict; self.reason = reason; self.sessionPrescription = sessionPrescription
        self.baselineNights = baselineNights; self.inputsDigest = inputsDigest; self.computedAt = computedAt
    }

    enum CodingKeys: String, CodingKey {
        case date, verdict, reason
        case sessionPrescription = "session_prescription"
        case baselineNights = "baseline_nights"
        case inputsDigest = "inputs_digest"
        case computedAt = "computed_at"
    }
}

/// The hub's reply (`hub_verdict` = its own verdict for the date, nil when it has none yet).
/// Decoded with `JSON.decoder` (snake_case → camelCase).
public struct OnDeviceVerdictStored: Codable, Sendable, Equatable {
    public var date: String
    public var verdict: String
    public var hubVerdict: String?
    public var receivedAt: String
    public init(date: String, verdict: String, hubVerdict: String?, receivedAt: String) {
        self.date = date; self.verdict = verdict; self.hubVerdict = hubVerdict; self.receivedAt = receivedAt
    }
}

/// B-44 Option B: the on-device verdict the gate and Decide read instead of the hub's, laid over
/// the hub's `/planning/morning` + `/planning/morning-verdict` answers (every other field — override,
/// gate answer, strain, carbs — stays the hub's). `nil` = the phone has no verdict for `day`
/// (no Apple night yet, HealthKit unavailable): the hub's verdict is kept as the fallback.
public protocol MorningVerdictOverlay: Sendable {
    func verdict(day: String) async -> OnDeviceMorning?
    /// The phone's local day key (`yyyy-MM-dd`).
    var todayKey: String { get }
}

/// One morning's on-device verdict in the hub's vocabulary.
public struct OnDeviceMorning: Codable, Sendable, Equatable {
    public var day: String
    public var verdict: String
    public var reason: String?
    public var sessionPrescription: String?
    public var gateSignals: [GateSignal]
    public var computedAt: String
    public init(day: String, verdict: String, reason: String?, sessionPrescription: String?, gateSignals: [GateSignal], computedAt: String) {
        self.day = day; self.verdict = verdict; self.reason = reason; self.sessionPrescription = sessionPrescription
        self.gateSignals = gateSignals; self.computedAt = computedAt
    }
}

extension MorningResponse {
    /// The hub's response with the on-device verdict for `morning.day` in place of the hub's.
    public func overlaid(with morning: OnDeviceMorning) -> MorningResponse {
        var r = self
        r.verdict = morning.verdict
        r.verdictDate = morning.day
        r.isStale = false
        r.gateSignals = Self.mergedSignals(hub: gateSignals, phone: morning.gateSignals)
        r.verdictComputedAt = morning.computedAt
        return r
    }

    /// RG-05 / B-121: per-key merge — the phone replaces only the keys it computes (hrv, sleep_h,
    /// rhr, …) in the hub's order; hub-only rows (`load` with its "Paused · since …" note) stay;
    /// phone-only keys follow in the phone's order.
    static func mergedSignals(hub: [GateSignal]?, phone: [GateSignal]) -> [GateSignal] {
        guard let hub, !hub.isEmpty else { return phone }
        let byKey = Dictionary(phone.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let hubKeys = Set(hub.map(\.key))
        return hub.map { byKey[$0.key] ?? $0 } + phone.filter { !hubKeys.contains($0.key) }
    }
}

extension OnDeviceMorning {
    public var asMorningVerdict: MorningVerdict {
        .onDevice(date: day, verdict: verdict, reason: reason, sessionPrescription: sessionPrescription, computedAt: computedAt)
    }
}

/// RG-12 / B-127: the day's FIRST on-device verdict, frozen — later nights, overlays and relaunches
/// never rewrite "YOUR CALL FOR TODAY · HH:mm", the word or the rows.
public protocol FrozenMorningStoring: Sendable {
    func frozen(day: String) -> OnDeviceMorning?
    func freeze(_ morning: OnDeviceMorning)
}

/// `UserDefaults`-backed (survives relaunch and background wakes); keeps the last 7 days.
public struct UserDefaultsFrozenMorningStore: FrozenMorningStoring {
    public static let key = "ji.ondevice.verdict.frozen"
    // UserDefaults is thread-safe by documented contract (not annotated Sendable on this SDK).
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func map() -> [String: Data] { (defaults.dictionary(forKey: Self.key) as? [String: Data]) ?? [:] }

    public func frozen(day: String) -> OnDeviceMorning? {
        guard let data = map()[day] else { return nil }
        return try? JSONDecoder().decode(OnDeviceMorning.self, from: data)
    }

    public func freeze(_ morning: OnDeviceMorning) {
        guard let data = try? JSONEncoder().encode(morning) else { return }
        var m = map()
        m[morning.day] = data
        let keep = Set(m.keys.sorted().suffix(7))
        defaults.set(m.filter { keep.contains($0.key) }, forKey: Self.key)
    }
}

public enum OnDeviceMorningFreeze {
    /// The frozen verdict for `day` when one exists (`fresh == false`, `make` is not called);
    /// otherwise `make()` and, when it yields a verdict, freezes it (`fresh == true`).
    /// `nil` = no verdict yet (nothing frozen, the next call tries again).
    public static func resolve(day: String, store: any FrozenMorningStoring,
                               make: () async -> OnDeviceMorning?) async -> (morning: OnDeviceMorning, fresh: Bool)? {
        if let hit = store.frozen(day: day) { return (hit, false) }
        guard let m = await make() else { return nil }
        store.freeze(m)
        return (m, true)
    }
}
