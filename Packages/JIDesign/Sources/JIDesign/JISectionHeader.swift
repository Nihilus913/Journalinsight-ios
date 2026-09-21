import SwiftUI

/// §2: the uppercase footnote header above a card group (Health / Settings idiom). Pure so the
/// text transform is testable without a window.
public nonisolated func sectionHeaderTitle(_ title: String) -> String { title.uppercased() }

public struct JISectionHeader: View {
    private let title: String
    @Environment(\.jiTheme) private var theme
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(sectionHeaderTitle(title))
            .jiFont(.footnote)
            .foregroundStyle(theme.color(.muted))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}
