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

    // Held by the App struct (not RootTabView's own @State) so a cold-start deep link — the
    // Info.plist-registered `ji`/`journalinsight` URL types resolve to `.onOpenURL` before
    // RootTabView has necessarily finished its first `.task` — has somewhere durable to land;
    // RootTabView reads it via `.onChange` and clears it once handled so re-opening the app
    // without a new URL doesn't replay a stale one.
    @State private var pendingDeepLink: DeepLink?

    var body: some Scene {
        WindowGroup {
            RootTabView(env: env, pendingDeepLink: $pendingDeepLink)
                .preferredColorScheme(.dark)
                .tint(JIColor.info)
                .onOpenURL { url in
                    guard let link = DeepLink.parse(url) else { return }
                    pendingDeepLink = link
                }
        }
    }
}
