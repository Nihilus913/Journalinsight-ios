import Foundation

/// Reads/writes a `HubSnapshot` to App-Group `UserDefaults`, for the widget
/// extension (and the app) to share the latest hub state without either
/// process touching the Keychain-held connection token.
///
/// `UserDefaults(suiteName:)` returns `nil` when the app group is
/// unavailable (e.g. missing entitlement, bogus suite name). That case is
/// handled gracefully everywhere here: `read()` returns `nil`, `write(_:)`
/// is a silent no-op — never a crash, never a force-unwrap.
public struct SnapshotStore: Sendable {
    private static let key = "ji.snapshot.v1"

    // UserDefaults is thread-safe by documented contract but predates Sendable annotation
    // on this SDK; nonisolated(unsafe) reflects that instead of losing SnapshotStore's own
    // Sendable conformance (still `let`, still never mutated after init).
    private nonisolated(unsafe) let defaults: UserDefaults?

    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    /// Test/DI seam: inject a `UserDefaults` double directly (or `nil` to stand in for a
    /// genuinely unavailable app group) instead of routing through `UserDefaults(suiteName:)`.
    /// That initializer's handling of an invalid suite name isn't guaranteed across toolchains
    /// — e.g. the Xcode 27 RC resolves `suiteName: ""` to the real standard-defaults domain
    /// rather than returning `nil` — so a bogus-name string can no longer stand in for
    /// "unavailable" in tests.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public func read() -> HubSnapshot? {
        guard let defaults, let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(HubSnapshot.self, from: data)
    }

    public func write(_ snapshot: HubSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
