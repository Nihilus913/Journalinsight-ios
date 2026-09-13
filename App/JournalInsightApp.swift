import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub

@main
struct JournalInsightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // CODE-2: a boot-time Keychain READ error (e.g. transient Secure Enclave/first-unlock failure)
    // must not crash launch — treat it like "no token yet" and let RootTabView present the
    // Connection sheet (env.needsConnection) instead. Only a failure to construct the environment
    // itself (cache/prefs storage) is still fatal.
    @State private var env: AppEnvironment = {
        do {
            let e = try AppEnvironment()
            do { try e.boot() } catch { e.needsConnection = true }
            return e
        } catch { fatalError("AppEnvironment init failed: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView(env: env)
                .preferredColorScheme(.dark)
                .tint(JIColor.info)
        }
    }
}
