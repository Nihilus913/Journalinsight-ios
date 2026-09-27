import Foundation

/// §8.5 one cell of the screenshot sweep. Sizes are points (portrait unless the name says
/// landscape). iPad rows are added when §8.3 turns iPad on.
public nonisolated struct SweepCell: Sendable, Hashable {
    public let device: String, width: CGFloat, height: CGFloat, dark: Bool, ax: Bool
    /// W-GUI F10: the accessibility material variant of the cell.
    public let variant: SweepVariant
    public init(device: String, width: CGFloat, height: CGFloat, dark: Bool, ax: Bool, variant: SweepVariant = .none) {
        self.device = device; self.width = width; self.height = height; self.dark = dark; self.ax = ax; self.variant = variant
    }
    public var fileStem: String {
        "\(device)-\(Int(width))x\(Int(height))-\(dark ? "dark" : "light")-\(ax ? "ax3" : "default")" + variant.fileSuffix
    }
}

/// W-GUI F10 (report §4.1 E10 / E2): Reduce Transparency (opaque cards) and Increase Contrast
/// (1.5 pt rim, no ring glow) are sweep cells of their own, forced through the JIDesign
/// environment overrides (`jiAccessibilityOverrides`) — the system keys are read-only.
public nonisolated enum SweepVariant: String, Sendable, Hashable, CaseIterable {
    case none, rt, ic
    public var fileSuffix: String { self == .none ? "" : "-\(rawValue)" }
    public var reduceTransparency: Bool? { self == .rt ? true : nil }
    public var increaseContrast: Bool? { self == .ic ? true : nil }
}

public nonisolated enum SweepMatrix {
    public static let sizes: [(device: String, width: CGFloat, height: CGFloat)] = [
        ("iphone18pro", 393, 852),
        ("iphone18promax", 440, 956),
        ("iphone18promax-landscape", 956, 440),
    ]
    public static var cells: [SweepCell] {
        sizes.flatMap { s in
            [false, true].flatMap { dark in
                [false, true].map { ax in SweepCell(device: s.device, width: s.width, height: s.height, dark: dark, ax: ax) }
            }
        } + [
            // W-GUI F10: the two material fallbacks, on the phone row, dark, default type size.
            SweepCell(device: "iphone18pro", width: 393, height: 852, dark: true, ax: false, variant: .rt),
            SweepCell(device: "iphone18pro", width: 393, height: 852, dark: true, ax: false, variant: .ic),
        ]
    }
}
