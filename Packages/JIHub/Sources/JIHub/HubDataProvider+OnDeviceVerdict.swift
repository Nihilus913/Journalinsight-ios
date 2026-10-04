import JICore

/// B-44 Option B — the phone's morning verdict upload (`plan.ondevice_verdict`, HT migration 077).
extension HubDataProvider: OnDeviceVerdictUploading {
    public func uploadOnDeviceVerdict(_ body: OnDeviceVerdictUpload) async throws -> OnDeviceVerdictStored {
        try await client.send("POST", "/api/v1/planning/ondevice-verdict", body: body)
    }
}
