import Testing
@testable import JICore

@Test(arguments: [
    (401, "bad token", HubError.unauthorized),
    (409, "already logged", HubError.duplicate(detail: "already logged")),
    (502, "yazio session", HubError.yazioAuthExpired(detail: "yazio session")),
    (422, "window_days<=365", HubError.http(status: 422, detail: "window_days<=365")),
])
func statusMapsToNamedCase(status: Int, detail: String, expected: HubError) {
    #expect(HubError.from(status: status, detail: detail) == expected)
}
