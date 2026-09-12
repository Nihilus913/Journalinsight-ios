import SwiftUI
import JICore

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { Text("Today — JICore \(JICore.version)") }
            Tab("Recovery", systemImage: "heart") { Text("Recovery") }
        }
    }
}
