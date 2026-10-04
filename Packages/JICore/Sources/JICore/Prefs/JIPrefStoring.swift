import Foundation

/// W-B31 R-2: the 3-method key → JSON-blob prefs seam. `JIPersistence.PrefStore` conforms (its
/// own API, verbatim); lets a package that cannot depend on JIPersistence (JIDesign —
/// `HapticsPrefsStore`) read and write prefs. Implementations must be thread-safe.
public protocol JIPrefStoring: Sendable {
    func get<T: Decodable>(_ key: String, as: T.Type) throws -> T?
    func set<T: Encodable>(_ key: String, _ value: T) throws
    func remove(_ key: String) throws
}
