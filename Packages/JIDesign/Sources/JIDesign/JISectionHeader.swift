import SwiftUI

/// B-47 — the section header above a card group. **Spec §2 exception:** the uppercase-footnote
/// idiom is retired. Bevel and Apple Fitness (`docs/design/references/2026-09-22-*.png`) both set
/// a group title as a title-case bold card title at the body-plus size; uppercasing a 13 pt
/// footnote is exactly the "back to the scaling" that made our screens read as a dense RN port.
/// The transform is kept as a pure seam (it is the one place the idiom could change again) and
/// now returns the title unchanged.
public nonisolated func sectionHeaderTitle(_ title: String) -> String { title }

public struct JISectionHeader: View {
    private let title: String
    @Environment(\.jiTheme) private var theme
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(sectionHeaderTitle(title))
            .jiFont(.cardTitle)
            .foregroundStyle(theme.color(.text))
            // B-57 W1 r5: a long header wraps at accessibility sizes instead of truncating.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}
