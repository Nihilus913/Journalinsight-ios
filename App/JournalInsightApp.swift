import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub

@main
struct JournalInsightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var env: AppEnvironment = { do { let e = try AppEnvironment(); try e.boot(); return e } catch { fatalError("AppEnvironment boot failed: \(error)") } }()

    var body: some Scene {
        WindowGroup {
            RootTabView(env: env)
                .preferredColorScheme(.dark)
                .tint(JIColor.info)
        }
    }
}
