import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub

struct RootTabView: View {
    @Bindable var env: AppEnvironment
    @State private var showConnection = false
    @State private var todayModel: TodayViewModel?

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                Group {
                    if let store = env.providerStore {
                        if let todayModel {
                            TodayView(model: todayModel, onOpenConnection: { showConnection = true })
                        } else {
                            ProgressView()
                                .task { todayModel = TodayViewModel(provider: store.provider, cache: env.cache) }
                        }
                    } else {
                        ContentUnavailableView { Label("Connect to your hub", systemImage: "server.rack") } description: { Text("Enter the HealthTraining hub URL and token.") } actions: {
                            Button("Connection…") { showConnection = true }.buttonStyle(.pressableScale)
                        }
                    }
                }
            }
            Tab("Recovery", systemImage: "heart") { Text("Recovery — W2").foregroundStyle(JIColor.muted) }
        }
        .background(JIColor.bg)
        .onAppear { if env.needsConnection { showConnection = true } }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(store: ConnectionConfigStore(secrets: env.secrets)) { config in
                env.apply(config)
                todayModel = nil
            }
        }
    }
}
