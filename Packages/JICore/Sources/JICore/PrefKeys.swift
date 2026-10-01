import Foundation

/// W-SSOT-1 SS-6 (audit 01-P7): shared UserDefaults / App-Group keys. One literal, read by
/// JIFeatures and written by JIHealthKit — both depend on JICore, neither on the other's key.
public nonisolated enum PrefKeys {
    /// ISO-8601 (UTC) instant of the last 2xx HealthKit upload POST (B-65), App-Group suite.
    public static let hkLastUploadSuccess = "hk.upload.lastSuccess"
}
