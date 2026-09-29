import Foundation

/// Settings › Apple Health › "HRV for other apps" (Toby 2026-09-29). On (default): the backload
/// also writes Garmin HRV as classic "Heart Rate Variability" (SDNN type), which Bevel and most
/// third-party apps read; the native RMSSD ("Recovery HRV") copy is written either way.
/// Stored in the App-Group suite next to the backload cursor.
public enum HrvForOtherApps {
    public static let key = "hk.backload.hrvForOtherApps"
    public static func isOn(_ defaults: UserDefaults?) -> Bool {
        (defaults?.object(forKey: key) as? Bool) ?? true
    }
    public static func set(_ on: Bool, defaults: UserDefaults?) { defaults?.set(on, forKey: key) }
}
