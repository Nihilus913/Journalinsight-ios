import SwiftUI

/// §2b.2 the 44-pt inset-grouped row: optional tinted symbol, title + subtitle, trailing value.
/// Put it inside a `List` `Section`; add `NavigationLink`/swipe actions at the call site.
public struct JIRow<Trailing: View>: View {
    public nonisolated static var minHeight: CGFloat { 44 }
    let title: String, subtitle: String?, systemImage: String?, tint: Color?, trailing: Trailing
    @Environment(\.jiTheme) private var theme

    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.tint = tint; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint ?? theme.color(.info)).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).jiFont(.body).foregroundStyle(theme.color(.text))
                if let subtitle { Text(subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            Spacer(minLength: 8)
            trailing.foregroundStyle(theme.color(.muted))
        }
        .frame(minHeight: Self.minHeight)
    }
}

public extension JIRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}
