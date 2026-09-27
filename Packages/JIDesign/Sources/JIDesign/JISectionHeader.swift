import SwiftUI

/// W-GUI S2 — report §4.5 "Section header": 13 pt bold caps, inset 16 so the header text starts
/// where the card text starts (16 + 16), 24 pt above / 8 pt below. This restores the caps idiom
/// the mockups use (B-47 had retired it for a title-case card title; the 2026-09-25 mockups
/// settle it the other way). The transform stays the one seam for the idiom.
public nonisolated enum JISectionHeaderMetrics {
    public static let inset: CGFloat = JISpacing.s4
    public static let above: CGFloat = JISpacing.s6
    public static let below: CGFloat = JISpacing.s2
}

public nonisolated func sectionHeaderTitle(_ title: String) -> String { title.uppercased() }

public struct JISectionHeader: View {
    private let title: String
    @Environment(\.jiTheme) private var theme
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(sectionHeaderTitle(title))
            .jiFont(.footnote, weight: .bold)
            .foregroundStyle(theme.color(.muted))
            // B-57 W1 r5: a long header wraps at accessibility sizes instead of truncating.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, JISectionHeaderMetrics.inset)
            .padding(.top, JISectionHeaderMetrics.above)
            .padding(.bottom, JISectionHeaderMetrics.below)
            .accessibilityAddTraits(.isHeader)
    }
}
