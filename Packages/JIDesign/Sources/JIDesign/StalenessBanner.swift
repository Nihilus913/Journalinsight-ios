import SwiftUI

/// PARITY-3: `hubReachable == false` must mean a genuine network outage (`HubError.network`) only —
/// callers must not route a 401 (`HubError.unauthorized`) through this flag, since that is a token
/// problem to be surfaced as an error card with a Connection action, not "stale data, hub unreachable".
public struct StalenessBanner: View {
    let fetchedAt: Date?, hubReachable: Bool
    public init(fetchedAt: Date?, hubReachable: Bool) { self.fetchedAt = fetchedAt; self.hubReachable = hubReachable }
    public var body: some View {
        if !hubReachable, let fetchedAt {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text("Showing data from \(fetchedAt.formatted(date: .omitted, time: .shortened)) — hub unreachable")
            }
            .font(.footnote).foregroundStyle(JIColor.text)
            .padding(10).frame(maxWidth: .infinity)
            .background(JIColor.surface3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
