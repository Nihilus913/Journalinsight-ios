import Foundation
import Testing
import JIHub
@testable import JIFeatures

@Test @MainActor func connectionModelValidatesAndSaves() throws {
    let store = ConnectionConfigStore(secrets: InMemorySecretStore())
    let m = ConnectionSheetModel(store: store)
    m.baseURL = "not a url"; m.token = ""
    #expect(try m.save() == nil)
    m.baseURL = "http://192.168.1.158:8000"; m.token = "abc"
    let saved = try #require(try m.save())
    #expect(saved.baseURL.absoluteString == "http://192.168.1.158:8000")
    #expect(try store.load() == saved)
}

/// An invalid candidate must short-circuit before any network call — `.other(...)` is set
/// synchronously off `candidate == nil`, never a `ConnectionTest.run` outcome.
@Test @MainActor func connectionModelTestWithInvalidCandidateSkipsNetwork() async throws {
    let store = ConnectionConfigStore(secrets: InMemorySecretStore())
    let m = ConnectionSheetModel(store: store)
    m.baseURL = "not a url"; m.token = ""
    await m.test()
    guard case .other = m.status else {
        Issue.record("expected .other, got \(String(describing: m.status))")
        return
    }
    #expect(m.testing == false)
}

/// An existing saved config must pre-fill the fields on init, not start from the "http://" placeholder.
@Test @MainActor func connectionModelPrefillsFromExistingSavedConfig() throws {
    let store = ConnectionConfigStore(secrets: InMemorySecretStore())
    try store.save(ConnectionConfig(baseURL: try #require(URL(string: "http://10.0.0.5:8000")), token: "secret-token"))
    let m = ConnectionSheetModel(store: store)
    #expect(m.baseURL == "http://10.0.0.5:8000")
    #expect(m.token == "secret-token")
}

@Test @MainActor func connectionModelRejectsEmptyHostAndStripsNewlines() throws {
    let m = ConnectionSheetModel(store: ConnectionConfigStore(secrets: InMemorySecretStore()))
    m.baseURL = "https://:8000"; m.token = "abc"
    #expect(try m.save() == nil)
    m.baseURL = "http://192.168.1.163:8000\n"; m.token = "abc123\n"
    let saved = try #require(try m.save())
    #expect(saved.token == "abc123")
    #expect(saved.baseURL.host() == "192.168.1.163")
}
