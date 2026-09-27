import SwiftUI

/// W-GUI S2 — report §4.5 "Row": the inset-grouped row. 56 pt minimum, 12 pt vertical padding,
/// the symbol in a 32 pt well with a 10 pt radius, title + subtitle, trailing value; the
/// hairline between rows is `hairlineNested`, inset to the text. Put it inside a `JIGroupedCard`
/// or a `List` `Section`; add `NavigationLink` / swipe actions at the call site.
public nonisolated enum JIRowMetrics {
    public static let minHeight: CGFloat = JITileHeight.row.base
    public static let verticalPadding: CGFloat = JISpacing.s3
    public static let iconWell: CGFloat = 32
    public static let iconWellRadius: CGFloat = 10
    /// Where the hairline starts: the icon well + the gap, so it aligns with the title.
    public static let hairlineInset: CGFloat = iconWell + JISpacing.s3
}

public struct JIRow<Trailing: View>: View {
    public nonisolated static var minHeight: CGFloat { JIRowMetrics.minHeight }
    let title: String, subtitle: String?, systemImage: String?, tint: Color?, trailing: Trailing
    @Environment(\.jiTheme) private var theme

    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.tint = tint; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: JISpacing.s3) {
            if let systemImage {
                let color = tint ?? theme.color(.info)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: JIRowMetrics.iconWell, height: JIRowMetrics.iconWell)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: JIRowMetrics.iconWellRadius, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).jiFont(.body).foregroundStyle(theme.color(.text))
                if let subtitle { Text(subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            Spacer(minLength: JISpacing.s2)
            trailing.foregroundStyle(theme.color(.muted))
        }
        .padding(.vertical, JIRowMetrics.verticalPadding)
        .frame(minHeight: JIRowMetrics.minHeight)
    }
}

public extension JIRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

/// The hairline between two rows of a grouped card (`hairlineNested`, inset to the title).
public struct JIRowDivider: View {
    @Environment(\.jiTheme) private var theme
    public init() {}
    public var body: some View {
        Rectangle().fill(theme.color(.hairlineNested)).frame(height: 1 / 3)
            .padding(.leading, JIRowMetrics.hairlineInset)
            .accessibilityHidden(true)
    }
}

/// W-GUI S2 — the grouped-list card: a level-1 `Surface` with 6 pt vertical / 16 pt horizontal
/// padding (report §4.5: rows carry their own 12). Rows go inside, `JIRowDivider` between them.
public struct JIGroupedCard<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) { content }
                .padding(.vertical, 6)
                .padding(.horizontal, JISpacing.s4)
        }
    }
}
