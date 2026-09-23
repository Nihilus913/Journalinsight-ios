import Foundation

/// W-B57b — `MockDataProvider`'s `VerdictOverrideProviding` conformance. No bundled fixture (a
/// POST echo, same convention as `MockDataProvider+GateRespond.swift`); `session` mirrors the
/// hub's fixed strings for the choices that do not depend on the verdict text.
extension MockDataProvider: VerdictOverrideProviding {
    public func setVerdictOverride(date: String, choice: VerdictOverrideChoice, reason: String) async throws -> VerdictOverride {
        let session: String = switch choice {
        case .accept: "Easy Z2 30–40 min"
        case .full: "Full Upper"
        case .modified: "Easy Z2 30–40 min"
        case .rest: "Rest — walks only"
        }
        return VerdictOverride(date: date, choice: choice, reason: reason.isEmpty ? nil : reason,
                               session: session, createdAt: "\(date)T06:00:00+02:00")
    }

    public func clearVerdictOverride(date: String) async throws {}
}
